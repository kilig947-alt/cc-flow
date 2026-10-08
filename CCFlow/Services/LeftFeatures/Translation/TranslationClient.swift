import Foundation
import CryptoKit
import NaturalLanguage
import CoreServices

struct TranslationClient {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    static func detectedLanguage(_ text: String) -> TranslationLanguage {
        recognizedLanguage(text) ?? .en
    }

    static func recognizedLanguage(_ text: String) -> TranslationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage?.rawValue else { return nil }
        if language.hasPrefix("zh") { return .zh }
        return TranslationLanguage(rawValue: language)
    }

    static func youdaoInput(_ text: String) -> String {
        // Follow the API's Unicode code-point length (Swift Character counts grapheme clusters).
        let scalars = text.unicodeScalars
        return scalars.count <= 20 ? text
            : String(String.UnicodeScalarView(scalars.prefix(10))) + String(scalars.count)
                + String(String.UnicodeScalarView(scalars.suffix(10)))
    }

    static func aiURL(base: String, path: String) throws -> URL {
        guard var url = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)),
              !path.contains("?"), !path.contains("#"), !path.contains("://") else {
            throw TranslationFailure.message(AppLocalization.runtimeString("translation.api_url_must_use_https_http_is_allowed"))
        }
        url.path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map(String.init).joined(separator: "/")
        url.path = "/" + ([url.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/"))
        url.query = nil
        url.fragment = nil
        guard let result = url.url else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.invalid_api_url")) }
        return result
    }

    func translate(_ text: String, source: TranslationLanguage, target: TranslationLanguage,
                   configuration c: TranslationServiceConfiguration, secret: String) async throws -> String {
        if c.provider == .dictionary {
            guard text.count <= 200, let definition = DCSCopyTextDefinition(nil, text as CFString, CFRange(location: 0, length: (text as NSString).length)) else {
                throw TranslationFailure.message(AppLocalization.runtimeString("translation.no_dictionary_entry_found_use_a_word_or"))
            }
            return definition.takeRetainedValue() as String
        }
        let request = try Self.request(text, source: source, target: target, configuration: c, secret: secret)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranslationFailure.message(AppLocalization.runtimeFormat("translation.request_failed_http_check_key_quota_and_network", c.provider.title, String(describing: status)))
        }
        return try Self.parse(data, provider: c.provider)
    }

    static func request(_ text: String, source: TranslationLanguage, target: TranslationLanguage,
                        configuration c: TranslationServiceConfiguration, secret: String,
                        salt: String = UUID().uuidString, timestamp: String = String(Int(Date().timeIntervalSince1970))) throws -> URLRequest {
        let provider = c.provider
        if provider.requiresSecret && secret.isEmpty {
            throw TranslationFailure.message(AppLocalization.runtimeFormat("translation.enter_the_key_in_service_settings_first", provider.title))
        }
        let from = source.code(for: provider), to = target.code(for: provider)
        var endpoint = ""
        var form: [String: String] = [:]
        var json: Any?
        var headers: [String: String] = [:]
        switch provider {
        case .myMemory:
            guard text.utf8.count <= 500 else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.mymemory_allows_up_to_500_utf_8_bytes")) }
            endpoint = "https://api.mymemory.translated.net/get"
            let resolvedSource = source == .auto ? detectedLanguage(text) : source
            form = ["q": text, "langpair": resolvedSource.code(for: provider) + "|" + to]
        case .baidu:
            guard !c.appID.isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_baidu_app_id")) }
            endpoint = "https://fanyi-api.baidu.com/api/trans/vip/translate"
            let sign = Insecure.MD5.hash(data: Data((c.appID + text + salt + secret).utf8)).map { String(format: "%02x", $0) }.joined()
            form = ["q": text, "from": from, "to": to, "appid": c.appID, "salt": salt, "sign": sign]
        case .youdao:
            guard !c.appID.isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_youdao_app_id")) }
            endpoint = "https://openapi.youdao.com/api"
            let sign = SHA256.hash(data: Data((c.appID + youdaoInput(text) + salt + timestamp + secret).utf8)).map { String(format: "%02x", $0) }.joined()
            form = ["q": text, "from": from, "to": to, "appKey": c.appID, "salt": salt, "sign": sign, "signType": "v3", "curtime": timestamp, "strict": "true"]
        case .microsoft:
            var url = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
            url.queryItems = [URLQueryItem(name: "api-version", value: "3.0"), URLQueryItem(name: "to", value: to)]
            if source != .auto { url.queryItems?.append(URLQueryItem(name: "from", value: from)) }
            endpoint = url.url!.absoluteString
            headers["Ocp-Apim-Subscription-Key"] = secret
            if !c.region.isEmpty { headers["Ocp-Apim-Subscription-Region"] = c.region }
            json = [["Text": text]]
        case .deepL:
            endpoint = "https://api-free.deepl.com/v2/translate"
            headers["Authorization"] = "DeepL-Auth-Key \(secret)"
            var body: [String: Any] = ["text": [text], "target_lang": to]
            if source != .auto { body["source_lang"] = from }
            json = body
        case .dictionary:
            throw TranslationFailure.message(AppLocalization.runtimeString("translation.system_dictionary_does_not_use_a_network_api"))
        case .volcano:
            var body: [String: Any] = ["TextList": [text], "TargetLanguage": to]
            if source != .auto { body["SourceLanguage"] = from }
            var request = try TranslationCloudSigning.jsonRequest("https://translate.volcengineapi.com/?Action=TranslateText&Version=2020-06-01", body: body)
            try TranslationCloudSigning.signV4(&request, accessKey: c.appID, secret: secret, region: c.region.isEmpty ? "cn-north-1" : c.region, service: "translate", volc: true)
            return request
        case .amazon:
            let region = c.region.isEmpty ? "us-east-1" : c.region
            guard region.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.invalid_aws_region_format")) }
            let domain = region.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
            var request = try TranslationCloudSigning.jsonRequest("https://translate.\(region).\(domain)/", body: ["Text": text, "SourceLanguageCode": from, "TargetLanguageCode": to])
            request.setValue("AWSShineFrontendService_20170701.TranslateText", forHTTPHeaderField: "X-Amz-Target")
            request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
            try TranslationCloudSigning.signV4(&request, accessKey: c.appID, secret: secret, region: region, service: "translate")
            return request
        case .aliyun:
            return try TranslationCloudSigning.aliyun(text: text, source: from, target: to, accessKey: c.appID, secret: secret, region: c.region)
        case .caiyun:
            endpoint = "https://api.interpreter.caiyunai.com/v1/translator"
            headers["X-Authorization"] = "token " + secret
            json = ["source": [text], "trans_type": from + "2" + to, "detect": source == .auto, "request_id": salt]
        case .niutrans:
            endpoint = "https://api.niutrans.com/NiuTransServer/translation"
            form = ["from": from, "to": to, "apikey": secret, "src_text": text]
        case .google:
            endpoint = "https://translation.googleapis.com/language/translate/v2"
            headers["X-Goog-Api-Key"] = secret
            var body = ["q": text, "target": to, "format": "text"]
            if source != .auto { body["source"] = from }
            json = body
        default:
            guard !c.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_an_ai_model_name")) }
            endpoint = try aiURL(base: c.baseURL, path: c.apiPath).absoluteString
            if !secret.isEmpty { headers["Authorization"] = "Bearer \(secret)" }
            let prompt = c.prompt.replacingOccurrences(of: "{source}", with: source.promptName).replacingOccurrences(of: "{target}", with: target.promptName)
            json = ["model": c.model, "stream": false, "messages": [["role": "system", "content": prompt], ["role": "user", "content": text]]]
            if provider == .claude {
                headers.removeValue(forKey: "Authorization")
                headers["x-api-key"] = secret
                headers["anthropic-version"] = "2023-06-01"
                json = ["model": c.model, "max_tokens": 8192, "system": prompt, "messages": [["role": "user", "content": text]]]
            } else if provider == .azureOpenAI {
                headers.removeValue(forKey: "Authorization")
                headers["api-key"] = secret
            }
        }
        var url = URLComponents(string: endpoint)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = form.sorted { $0.key < $1.key }.map {
            $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
        if provider == .myMemory { url.percentEncodedQuery = encoded }
        var request = URLRequest(url: url.url!, timeoutInterval: 30)
        request.httpMethod = provider == .myMemory ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if provider != .myMemory {
            request.httpBody = Data(encoded.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    static func parse(_ data: Data, provider: TranslationProvider) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let dict = object as? [String: Any] ?? [:]
        let result: String?
        switch provider {
        case .myMemory:
            guard (dict["responseStatus"] as? NSNumber)?.intValue == 200 else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.mymemory_quota_exceeded_or_language_unsupported")) }
            result = (dict["responseData"] as? [String: Any])?["translatedText"] as? String
        case .baidu:
            if let code = dict["error_code"] { throw TranslationFailure.message(AppLocalization.runtimeFormat("translation.baidu_translation_error_check_your_account_quota_and", String(describing: code))) }
            result = (dict["trans_result"] as? [[String: Any]])?.compactMap { $0["dst"] as? String }.joined(separator: "\n")
        case .youdao:
            guard dict["errorCode"] as? String == "0" else { throw TranslationFailure.message(AppLocalization.runtimeFormat("translation.youdao_translation_error_check_your_account_and_quota", String(describing: dict["errorCode"] ?? AppLocalization.runtimeString("translation.unknown")))) }
            result = (dict["translation"] as? [String])?.joined(separator: "\n")
        case .microsoft:
            result = ((object as? [[String: Any]])?.first?["translations"] as? [[String: Any]])?.first?["text"] as? String
        case .deepL:
            result = (dict["translations"] as? [[String: Any]])?.first?["text"] as? String
        case .volcano:
            result = (dict["TranslationList"] as? [[String: Any]])?.compactMap { $0["Translation"] as? String }.joined(separator: "\n")
        case .aliyun:
            result = (dict["Data"] as? [String: Any])?["Translated"] as? String
        case .amazon: result = dict["TranslatedText"] as? String
        case .caiyun: result = (dict["target"] as? [String])?.joined(separator: "\n") ?? dict["target"] as? String
        case .niutrans: result = dict["tgt_text"] as? String
        case .google:
            result = ((dict["data"] as? [String: Any])?["translations"] as? [[String: Any]])?.compactMap { $0["translatedText"] as? String }.joined(separator: "\n").mapHTMLEntities
        case .claude:
            result = (dict["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .dictionary: result = nil
        default:
            result = ((dict["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        }
        guard let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.service_returned_no_valid_translation")) }
        return result
    }
}

private extension String {
    // Google v2 returns HTML entities even for text input. Decode entities only; never interpret markup.
    var mapHTMLEntities: String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);|&(amp|lt|gt|quot|apos);", options: []) else { return self }
        var value = self
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)).reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let token = String(value[range])
            let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"]
            var replacement = named[token]
            if token.hasPrefix("&#") {
                let digits = String(token.dropFirst(2).dropLast())
                let code = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                replacement = code.flatMap(UnicodeScalar.init).map(String.init)
            }
            if let replacement { value.replaceSubrange(range, with: replacement) }
        }
        return value
    }
}
