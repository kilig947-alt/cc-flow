import Foundation
import CryptoKit

/// The three cloud APIs use distinct signing scopes. Never log requests: headers contain credentials.
enum TranslationCloudSigning {
    static func hex(_ data: some Sequence<UInt8>) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func hash(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    static func hmac(_ key: Data, _ value: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
    }
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }
    static func form(_ values: [String: String]) -> String {
        values.sorted { $0.key < $1.key }.map { encode($0.key) + "=" + encode($0.value) }.joined(separator: "&")
    }
    static func date(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func jsonRequest(_ url: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: url), url.scheme == "https", url.host != nil else {
            throw TranslationFailure.message(AppLocalization.runtimeString("translation.invalid_cloud_service_url"))
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    static func signV4(_ request: inout URLRequest, accessKey: String, secret: String,
                       region: String, service: String, volc: Bool = false, now: Date = Date()) throws {
        guard !accessKey.isEmpty, !secret.isEmpty, !region.isEmpty, let url = request.url, let host = url.host else {
            throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_access_key_id_secret_key_and_service"))
        }
        let stamp = date(now, format: "yyyyMMdd'T'HHmmss'Z'")
        let day = String(stamp.prefix(8)), header = volc ? "x-date" : "x-amz-date"
        let bodyHash = hash(request.httpBody ?? Data())
        request.setValue(stamp, forHTTPHeaderField: header)
        request.setValue(host, forHTTPHeaderField: "Host")
        if volc { request.setValue(bodyHash, forHTTPHeaderField: "X-Content-Sha256") }
        var names = ["content-type", "host", header]
        if volc { names.append("x-content-sha256") }
        names.sort()
        let signed = names.joined(separator: ";")
        let canonicalHeaders = names.map { $0 + ":" + (request.value(forHTTPHeaderField: $0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) + "\n" }.joined()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let canonicalQuery = query.map { (encode($0.name), encode($0.value ?? "")) }.sorted { $0 < $1 }.map { $0 + "=" + $1 }.joined(separator: "&")
        let canonical = ["POST", url.path.isEmpty ? "/" : url.path, canonicalQuery, canonicalHeaders, signed, bodyHash].joined(separator: "\n")
        let terminator = volc ? "request" : "aws4_request"
        let algorithm = volc ? "HMAC-SHA256" : "AWS4-HMAC-SHA256"
        let scope = "\(day)/\(region)/\(service)/\(terminator)"
        let toSign = "\(algorithm)\n\(stamp)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        var key = hmac(Data(((volc ? "" : "AWS4") + secret).utf8), day)
        for value in [region, service, terminator] { key = hmac(key, value) }
        request.setValue("\(algorithm) Credential=\(accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(hex(hmac(key, toSign)))", forHTTPHeaderField: "Authorization")
    }
    static func tencent(body: [String: Any], service: String, action: String, version: String,
                        accessKey: String, secret: String, region: String, now: Date = Date()) throws -> URLRequest {
        guard !accessKey.isEmpty, !secret.isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_tencent_secretid_and_secretkey")) }
        var request = try jsonRequest("https://\(service).tencentcloudapi.com/", body: body)
        let host = request.url!.host!, stamp = String(Int(now.timeIntervalSince1970)), day = date(now, format: "yyyy-MM-dd")
        let canonical = "POST\n/\n\ncontent-type:application/json\nhost:\(host)\n\ncontent-type;host\n\(hash(request.httpBody!))"
        let scope = "\(day)/\(service)/tc3_request"
        let toSign = "TC3-HMAC-SHA256\n\(stamp)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        let key = hmac(hmac(hmac(Data(("TC3" + secret).utf8), day), service), "tc3_request")
        request.setValue("TC3-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=content-type;host, Signature=\(hex(hmac(key, toSign)))", forHTTPHeaderField: "Authorization")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(stamp, forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        return request
    }
    static func aliyun(text: String, source: String, target: String, accessKey: String, secret: String,
                       region: String, now: Date = Date(), nonce: String = UUID().uuidString) throws -> URLRequest {
        guard !accessKey.isEmpty, !secret.isEmpty else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.enter_alibaba_cloud_accesskey_id_and_secret")) }
        let region = region.isEmpty ? "cn-hangzhou" : region
        guard region.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw TranslationFailure.message(AppLocalization.runtimeString("translation.invalid_service_region_format")) }
        var fields = ["Action": "TranslateGeneral", "Version": "2018-10-12", "Format": "JSON", "AccessKeyId": accessKey,
                      "SignatureMethod": "HMAC-SHA1", "SignatureVersion": "1.0", "SignatureNonce": nonce,
                      "Timestamp": date(now, format: "yyyy-MM-dd'T'HH:mm:ss'Z'"), "FormatType": "text", "Scene": "general",
                      "SourceLanguage": source, "TargetLanguage": target, "SourceText": text]
        let toSign = "POST&%2F&" + encode(form(fields))
        fields["Signature"] = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(toSign.utf8), using: SymmetricKey(data: Data((secret + "&").utf8)))).base64EncodedString()
        var request = URLRequest(url: URL(string: "https://mt.\(region).aliyuncs.com/")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form(fields).utf8)
        return request
    }
}
