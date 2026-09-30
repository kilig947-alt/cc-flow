import Foundation
import AppKit
import Vision
import Combine

enum TranslationOCRProvider: String, Codable, CaseIterable, Identifiable {
    case system, volcano, tencent, tencentImage, baidu, youdao, google
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return AppLocalization.runtimeString("离线文本识别")
        case .volcano: return AppLocalization.runtimeString("火山 OCR")
        case .tencent: return AppLocalization.runtimeString("腾讯 OCR")
        case .tencentImage: return AppLocalization.runtimeString("腾讯图片翻译")
        case .baidu: return AppLocalization.runtimeString("百度 OCR")
        case .youdao: return AppLocalization.runtimeString("有道 OCR")
        case .google: return "Google OCR"
        }
    }
    var credentialLabel: String {
        switch self {
        case .tencent, .tencentImage: return "SecretId"
        case .volcano: return "Access Key ID"
        case .baidu: return "API Key"
        default: return AppLocalization.runtimeString("应用 ID")
        }
    }
    var needsID: Bool { self != .system && self != .google }
    var needsRegion: Bool { [.volcano, .tencent, .tencentImage].contains(self) }
    var account: String { "ocr." + rawValue }
    var documentationURL: URL {
        let paths: [Self: String] = [
            .system: "https://support.apple.com/guide/preview/copy-text-from-an-image-prvw625a5b2c/mac",
            .volcano: "https://www.volcengine.com/docs/86081/1660261",
            .tencent: "https://cloud.tencent.com/document/api/866/37173",
            .tencentImage: "https://cloud.tencent.com/document/product/551/118482",
            .baidu: "https://ai.baidu.com/ai-doc/OCR/zk3h7xz52",
            .youdao: "https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html",
            .google: "https://cloud.google.com/vision/docs/ocr"
        ]
        return URL(string: paths[self]!)!
    }
}

struct TranslationOCRConfiguration: Codable, Equatable {
    var provider: TranslationOCRProvider
    var appID = ""
    var region = ""
    static func preset(_ provider: TranslationOCRProvider) -> Self {
        Self(provider: provider, region: provider == .volcano ? "cn-north-1" : "ap-guangzhou")
    }
}

@MainActor
final class TranslationOCRSettings: ObservableObject {
    static let shared = TranslationOCRSettings()
    @Published private(set) var selected: TranslationOCRProvider
    @Published private(set) var configurations: [TranslationOCRConfiguration]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selected = defaults.string(forKey: "tflow.ocr.selected").flatMap(TranslationOCRProvider.init(rawValue:)) ?? .system
        let stored = defaults.data(forKey: "tflow.ocr.configurations").flatMap { try? JSONDecoder().decode([TranslationOCRConfiguration].self, from: $0) } ?? []
        configurations = TranslationOCRProvider.allCases.map { provider in stored.first { $0.provider == provider } ?? .preset(provider) }
    }
    func configuration(_ provider: TranslationOCRProvider) -> TranslationOCRConfiguration {
        configurations.first { $0.provider == provider } ?? .preset(provider)
    }
    func select(_ provider: TranslationOCRProvider) {
        selected = provider
        defaults.set(provider.rawValue, forKey: "tflow.ocr.selected")
    }
    func save(_ configuration: TranslationOCRConfiguration, secret: String) throws {
        try TranslationKeychain.write(secret.trimmingCharacters(in: .whitespacesAndNewlines), account: configuration.provider.account)
        guard let index = configurations.firstIndex(where: { $0.provider == configuration.provider }) else { return }
        configurations[index] = configuration
        defaults.set(try JSONEncoder().encode(configurations), forKey: "tflow.ocr.configurations")
    }
}

struct TranslationOCROutput {
    var text: String
    var translation: String?
}

struct TranslationOCRClient {
    var session: URLSession = .shared
    func recognize(_ data: Data, configuration c: TranslationOCRConfiguration, secret: String,
                   target: TranslationLanguage) async throws -> TranslationOCROutput {
        if c.provider == .system {
            return try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(data: data).perform([request])
                return TranslationOCROutput(text: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
            }.value
        }
        guard !secret.isEmpty, !c.provider.needsID || !c.appID.isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeFormat("请先配置 %@ 的凭据", AppLocalization.runtimeString(c.provider.title))) }
        // Clipboard images often arrive as TIFF; cloud APIs receive PNG only.
        let usesYoudao = c.provider == .youdao
        let png = try await Task.detached(priority: .userInitiated) {
            guard let image = NSBitmapImageRep(data: data), image.pixelsWide * image.pixelsHigh <= 40_000_000,
                  let png = image.representation(using: .png, properties: [:]), png.count <= 4 * 1024 * 1024 else {
                throw TranslationFailure.message(AppLocalization.runtimeString("云端 OCR 需 4 MB 以内的图片，请缩小截图区域"))
            }
            if usesYoudao && (min(image.pixelsWide, image.pixelsHigh) <= 10 || max(image.pixelsWide, image.pixelsHigh) >= 2048) {
                throw TranslationFailure.message(AppLocalization.runtimeString("有道 OCR 要求图片边长大于 10 且小于 2048 像素，请缩小截图区域或切换系统识别"))
            }
            return png
        }.value
        try Task.checkCancellation()
        var accessToken: String?
        if c.provider == .baidu {
            var tokenRequest = URLRequest(url: URL(string: "https://aip.baidubce.com/oauth/2.0/token")!, timeoutInterval: 30)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            tokenRequest.httpBody = Data(TranslationCloudSigning.form(["grant_type": "client_credentials", "client_id": c.appID, "client_secret": secret]).utf8)
            let tokenData = try await fetch(tokenRequest)
            let object = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any]
            accessToken = object?["access_token"] as? String
            guard accessToken != nil else { throw TranslationFailure.message("百度 OCR 认证失败，请检查 API Key 与 Secret Key") }
        }
        let request = try Self.request(png, configuration: c, secret: secret, target: target, baiduAccessToken: accessToken)
        return try Self.parse(await fetch(request), provider: c.provider)
    }
    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw TranslationFailure.message(AppLocalization.runtimeFormat("OCR 服务请求失败（HTTP %@），请检查凭据、额度与网络", String(describing: (response as? HTTPURLResponse)?.statusCode ?? 0)))
        }
        return data
    }
    static func request(_ png: Data, configuration c: TranslationOCRConfiguration, secret: String,
                        target: TranslationLanguage, baiduAccessToken: String? = nil,
                        now: Date = Date(), salt: String = UUID().uuidString) throws -> URLRequest {
        let image = png.base64EncodedString()
        if c.provider == .youdao && image.utf8.count >= 2 * 1024 * 1024 {
            throw TranslationFailure.message(AppLocalization.runtimeString("有道 OCR 要求编码后图片小于 2 MB，请缩小截图区域或切换系统识别"))
        }
        switch c.provider {
        case .system: throw TranslationFailure.message(AppLocalization.runtimeString("系统 OCR 不使用网络接口"))
        case .volcano:
            var request = try TranslationCloudSigning.jsonRequest("https://visual.volcengineapi.com/?Action=OCRNormal&Version=2020-08-26", body: ["image_base64": image])
            try TranslationCloudSigning.signV4(&request, accessKey: c.appID, secret: secret, region: c.region, service: "cv", volc: true, now: now)
            return request
        case .tencent, .tencentImage:
            let isImage = c.provider == .tencentImage
            return try TranslationCloudSigning.tencent(body: isImage ? ["Data": image, "Target": target == .auto ? "zh" : target.rawValue] : ["ImageBase64": image],
                service: isImage ? "tmt" : "ocr", action: isImage ? "ImageTranslateLLM" : "GeneralBasicOCR",
                version: isImage ? "2018-03-21" : "2018-11-19", accessKey: c.appID, secret: secret, region: c.region, now: now)
        case .google:
            var request = try TranslationCloudSigning.jsonRequest("https://vision.googleapis.com/v1/images:annotate", body: ["requests": [["image": ["content": image], "features": [["type": "DOCUMENT_TEXT_DETECTION"]]]]])
            request.setValue(secret, forHTTPHeaderField: "X-Goog-Api-Key")
            return request
        case .baidu, .youdao:
            var fields: [String: String]
            var url: URL
            if c.provider == .baidu {
                guard let token = baiduAccessToken else { throw TranslationFailure.message(AppLocalization.runtimeString("缺少百度 OCR 访问令牌")) }
                var components = URLComponents(string: "https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic")!
                components.queryItems = [URLQueryItem(name: "access_token", value: token)]
                url = components.url!
                fields = ["image": image, "detect_direction": "true"]
            } else {
                url = URL(string: "https://openapi.youdao.com/ocrapi")!
                let timestamp = String(Int(now.timeIntervalSince1970))
                let sign = TranslationCloudSigning.hash(Data((c.appID + TranslationClient.youdaoInput(image) + salt + timestamp + secret).utf8))
                fields = ["img": image, "langType": "auto", "detectType": "10012", "imageType": "1", "docType": "json", "appKey": c.appID, "salt": salt, "sign": sign, "signType": "v3", "curtime": timestamp]
            }
            var request = URLRequest(url: url, timeoutInterval: 45)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(TranslationCloudSigning.form(fields).utf8)
            return request
        }
    }
    static func parse(_ data: Data, provider: TranslationOCRProvider) throws -> TranslationOCROutput {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranslationFailure.message(AppLocalization.runtimeString("OCR 返回格式无效")) }
        var text: String?
        var translated: String?
        switch provider {
        case .system: break
        case .volcano:
            guard (root["code"] as? NSNumber)?.intValue == 10000 else { throw TranslationFailure.message("火山 OCR 识别失败，请检查凭据与额度") }
            text = ((root["data"] as? [String: Any])?["line_texts"] as? [String])?.joined(separator: "\n")
        case .tencent, .tencentImage:
            let response = root["Response"] as? [String: Any] ?? [:]
            guard response["Error"] == nil else { throw TranslationFailure.message("腾讯识别失败，请检查服务开通状态、凭据与额度") }
            if provider == .tencentImage {
                text = response["SourceText"] as? String
                translated = response["TargetText"] as? String
            } else { text = (response["TextDetections"] as? [[String: Any]])?.compactMap { $0["DetectedText"] as? String }.joined(separator: "\n") }
        case .baidu:
            guard root["error_code"] == nil else { throw TranslationFailure.message("百度 OCR 识别失败，请检查凭据与额度") }
            text = (root["words_result"] as? [[String: Any]])?.compactMap { $0["words"] as? String }.joined(separator: "\n")
        case .youdao:
            guard root["errorCode"] as? String == "0" else { throw TranslationFailure.message("有道 OCR 识别失败，请检查凭据与额度") }
            let regions = (root["Result"] as? [String: Any])?["regions"] as? [[String: Any]] ?? []
            text = regions.flatMap { $0["lines"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .google:
            let response = (root["responses"] as? [[String: Any]])?.first ?? [:]
            guard response["error"] == nil else { throw TranslationFailure.message("Google OCR 识别失败，请检查 API 开通状态与额度") }
            text = (response["fullTextAnnotation"] as? [String: Any])?["text"] as? String
                ?? (response["textAnnotations"] as? [[String: Any]])?.first?["description"] as? String ?? ""
        }
        guard let text else { throw TranslationFailure.message(AppLocalization.runtimeString("OCR 服务未返回有效识别结果")) }
        return TranslationOCROutput(text: text, translation: translated)
    }
}
