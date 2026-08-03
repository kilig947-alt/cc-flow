import Foundation

struct CompletionPromptStaticOption: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var reply: String

    nonisolated init(id: String = UUID().uuidString, title: String, reply: String) {
        self.id = id
        self.title = title
        self.reply = reply
    }
}

struct CompletionPromptRegexRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var isEnabled: Bool
    var triggerPattern: String
    var optionPattern: String
    var replyTemplate: String
    var staticOptions: [CompletionPromptStaticOption]
    var isFreeformOnly: Bool
    var allowsMultiple: Bool
    var capturesTriggerGroupsAsOptions: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case triggerPattern
        case optionPattern
        case replyTemplate
        case staticOptions
        case isFreeformOnly
        case allowsMultiple
        case capturesTriggerGroupsAsOptions
    }

    nonisolated init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        triggerPattern: String,
        optionPattern: String = "",
        replyTemplate: String = "选择 {key}：{option}",
        staticOptions: [CompletionPromptStaticOption] = [],
        isFreeformOnly: Bool = false,
        allowsMultiple: Bool = false,
        capturesTriggerGroupsAsOptions: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.triggerPattern = triggerPattern
        self.optionPattern = optionPattern
        self.replyTemplate = replyTemplate
        self.staticOptions = staticOptions
        self.isFreeformOnly = isFreeformOnly
        self.allowsMultiple = allowsMultiple
        self.capturesTriggerGroupsAsOptions = capturesTriggerGroupsAsOptions
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        triggerPattern = try container.decode(String.self, forKey: .triggerPattern)
        optionPattern = try container.decodeIfPresent(String.self, forKey: .optionPattern) ?? ""
        replyTemplate = try container.decodeIfPresent(String.self, forKey: .replyTemplate)
            ?? "选择 {key}：{option}"
        staticOptions = try container.decodeIfPresent(
            [CompletionPromptStaticOption].self,
            forKey: .staticOptions
        ) ?? []
        isFreeformOnly = try container.decodeIfPresent(Bool.self, forKey: .isFreeformOnly) ?? false
        allowsMultiple = try container.decodeIfPresent(Bool.self, forKey: .allowsMultiple) ?? false
        capturesTriggerGroupsAsOptions = try container.decodeIfPresent(
            Bool.self,
            forKey: .capturesTriggerGroupsAsOptions
        ) ?? false
    }

    nonisolated static let defaultTemplates: [CompletionPromptRegexRule] = [
        CompletionPromptRegexRule(
            id: "builtin-review-confirmation",
            name: "审阅与确认",
            triggerPattern: #"(?is)(?:请|请先|请你).{0,32}(?:审阅|审核)|(?:你|请).{0,12}确认后|确认后.{0,24}(?:继续|进入|开始)"#,
            staticOptions: [
                CompletionPromptStaticOption(
                    id: "confirm",
                    title: "确认，继续",
                    reply: "我已审阅并确认，请继续。"
                ),
                CompletionPromptStaticOption(
                    id: "revise",
                    title: "需要修改",
                    reply: "我需要先补充修改意见，请暂不要继续。"
                )
            ]
        ),
        CompletionPromptRegexRule(
            id: "builtin-listed-options",
            name: "字母或数字选项",
            triggerPattern: #"(?is)(?:请选择|请确认|希望包含哪些|你希望|选择哪|选项)|(?m)^\s*(?:A|1)[.．、)]\s+\S+"#,
            optionPattern: #"(?m)^\s*([A-Z]|\d{1,2})[.．、)]\s*(\S.*)$"#,
            replyTemplate: "选择 {key}：{option}"
        ),
        CompletionPromptRegexRule(
            id: "builtin-inline-or-options",
            name: "请选择 X 或 Y",
            triggerPattern: #"(?im)请选择\s*(?:[^：:\n]{1,40}[：:]\s*)?(.{1,160}?)\s*或(?:者)?\s*(.{1,160}?)(?:[？?。！!]|$)"#,
            replyTemplate: "选择 {key}：{option}",
            capturesTriggerGroupsAsOptions: true
        ),
        CompletionPromptRegexRule(
            id: "builtin-freeform-input",
            name: "自由输入",
            triggerPattern: #"(?im)^\s*(?:请告诉我|请提供|请输入|请补充|需要你提供|请回答).{0,240}(?:[？?：:]|$)"#,
            isFreeformOnly: true
        ),
        CompletionPromptRegexRule(
            id: "builtin-trailing-question-confirmation",
            name: "结尾问句确认",
            triggerPattern: #"(?s)[？?]\s*$"#,
            staticOptions: [
                CompletionPromptStaticOption(
                    id: "confirm",
                    title: "确认",
                    reply: "确认，请继续。"
                ),
                CompletionPromptStaticOption(
                    id: "yes",
                    title: "是的",
                    reply: "是的，请继续。"
                )
            ]
        )
    ]
}

struct CompletionPromptRegexMatch: Equatable, Sendable {
    let intervention: SessionIntervention
    let fingerprint: String
}

enum CompletionPromptRegexParser {
    nonisolated private static let maximumSourceLength = 40_000
    nonisolated private static let maximumPromptLength = 800
    nonisolated private static let maximumOptionLength = 300
    nonisolated private static let maximumOptionCount = 8

    nonisolated static func match(
        message: String,
        rules: [CompletionPromptRegexRule]
    ) -> CompletionPromptRegexMatch? {
        let source = sanitizedSource(message)
        guard !source.isEmpty else { return nil }

        for rule in rules where rule.isEnabled {
            guard matches(pattern: rule.triggerPattern, in: source) else { continue }

            let extractedOptions = rule.capturesTriggerGroupsAsOptions
                ? extractTriggerCaptureOptions(pattern: rule.triggerPattern, from: source)
                : extractOptions(pattern: rule.optionPattern, from: source)
            let optionPairs: [(title: String, reply: String)]
            if rule.isFreeformOnly {
                optionPairs = []
            } else if extractedOptions.count >= 2 {
                optionPairs = extractedOptions.map { option in
                    let title = "\(option.key). \(option.text)"
                    let reply = rule.replyTemplate
                        .replacingOccurrences(of: "{key}", with: option.key)
                        .replacingOccurrences(of: "{option}", with: option.text)
                    return (title, reply)
                }
            } else {
                optionPairs = rule.staticOptions.compactMap { option in
                    let title = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reply = option.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !reply.isEmpty else { return nil }
                    return (title, reply)
                }
            }

            guard !optionPairs.isEmpty || (rule.isFreeformOnly && optionPairs.isEmpty) else {
                continue
            }
            let prompt = extractedPrompt(from: source, optionPattern: rule.optionPattern)
            let fingerprint = stableFingerprint("\(rule.id)\n\(source)")
            let questionID = "completion-regex-question"
            let replyMap = Dictionary(uniqueKeysWithValues: optionPairs.map { ($0.title, $0.reply) })
            let replyMapJSON = encodeStringDictionary(replyMap) ?? "{}"
            let options = optionPairs.enumerated().map { index, pair in
                SessionInterventionOption(
                    id: "completion-option-\(index)",
                    title: pair.title,
                    detail: nil
                )
            }
            let question = SessionInterventionQuestion(
                id: questionID,
                header: rule.name,
                prompt: prompt,
                detail: "从本轮助手回复中识别",
                options: options,
                allowsMultiple: rule.allowsMultiple,
                allowsOther: rule.isFreeformOnly || optionPairs.count != 1,
                isSecret: false
            )
            let intervention = SessionIntervention(
                id: "completion-regex-\(fingerprint)",
                kind: .question,
                title: rule.name,
                message: prompt,
                options: options,
                questions: [question],
                supportsSessionScope: false,
                metadata: [
                    "source": "completionRegex",
                    "responseMode": "follow_up",
                    "completionPromptFingerprint": fingerprint,
                    "followUpRepliesJSON": replyMapJSON
                ]
            )
            return CompletionPromptRegexMatch(intervention: intervention, fingerprint: fingerprint)
        }

        return nil
    }

    nonisolated static func followUpMessage(
        for intervention: SessionIntervention,
        answers: [String: [String]]
    ) -> String? {
        let replyMap = decodeStringDictionary(intervention.metadata["followUpRepliesJSON"]) ?? [:]
        let questionOrder = intervention.resolvedQuestions.map(\.id)
        let orderedKeys = questionOrder + answers.keys.filter { !questionOrder.contains($0) }.sorted()
        let values = orderedKeys.flatMap { answers[$0] ?? [] }
        let replies = values.compactMap { rawValue -> String? in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return replyMap[value] ?? value
        }
        let result = replies.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    nonisolated static func validationError(for pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "正则不能为空" }
        do {
            _ = try NSRegularExpression(pattern: trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private nonisolated static func sanitizedSource(_ message: String) -> String {
        let clipped = String(message.prefix(maximumSourceLength))
        let withoutCodeFences = replacingMatches(
            pattern: #"(?s)```.*?```"#,
            in: clipped,
            with: ""
        )
        return withoutCodeFences.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func matches(pattern: String, in source: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let expression = try? NSRegularExpression(pattern: trimmed) else {
            return false
        }
        return expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }

    private nonisolated static func extractOptions(
        pattern: String,
        from source: String
    ) -> [(key: String, text: String)] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let expression = try? NSRegularExpression(pattern: trimmed) else {
            return []
        }

        var seen: Set<String> = []
        return expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).prefix(maximumOptionCount).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: source),
                  let textRange = Range(match.range(at: 2), in: source) else {
                return nil
            }
            let key = String(source[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(source[textRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumOptionLength)
            let normalizedText = String(text)
            guard !key.isEmpty, !normalizedText.isEmpty, seen.insert(key).inserted else { return nil }
            return (key, normalizedText)
        }
    }

    private nonisolated static func extractTriggerCaptureOptions(
        pattern: String,
        from source: String
    ) -> [(key: String, text: String)] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let expression = try? NSRegularExpression(pattern: trimmed),
              let match = expression.firstMatch(
                in: source,
                range: NSRange(source.startIndex..., in: source)
              ),
              match.numberOfRanges >= 3 else {
            return []
        }

        return (1..<min(match.numberOfRanges, maximumOptionCount + 1)).compactMap { index in
            guard let range = Range(match.range(at: index), in: source) else {
                return nil
            }
            let text = String(source[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "，,；;。！？!?：:"))
            guard !text.isEmpty else { return nil }
            let key = String(UnicodeScalar(64 + index)!)
            return (key, String(text.prefix(maximumOptionLength)))
        }
    }

    private nonisolated static func extractedPrompt(from source: String, optionPattern: String) -> String {
        var promptSource = source
        let trimmedPattern = optionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPattern.isEmpty,
           let expression = try? NSRegularExpression(pattern: trimmedPattern),
           let first = expression.firstMatch(
               in: source,
               range: NSRange(source.startIndex..., in: source)
           ),
           let range = Range(first.range, in: source) {
            promptSource = String(source[..<range.lowerBound])
        }

        let paragraphs = promptSource
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let candidate = paragraphs.last ?? promptSource
        return String(candidate.suffix(maximumPromptLength))
    }

    private nonisolated static func replacingMatches(
        pattern: String,
        in source: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: replacement
        )
    }

    private nonisolated static func encodeStringDictionary(_ value: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func decodeStringDictionary(_ value: String?) -> [String: String]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private nonisolated static func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
