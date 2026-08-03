//
//  SimilarOperationApprovalRule.swift
//  CCFlow
//
//  Session-local matching for repeated Codex hook permission requests.
//

import Foundation

struct SimilarOperationApprovalRule: Hashable, Sendable {
    let toolName: String
    let inputSignature: String

    nonisolated static func make(
        provider: SessionProvider,
        toolName: String?,
        toolInput: [String: AnyCodable]?
    ) -> SimilarOperationApprovalRule? {
        guard provider == .codex else { return nil }
        guard let normalizedToolName = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalizedToolName.isEmpty else {
            return nil
        }

        if normalizedToolName == "bash" || normalizedToolName == "shell" {
            guard let command = (toolInput?["command"]?.value as? String)
                ?? (toolInput?["cmd"]?.value as? String) else {
                return nil
            }
            let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCommand.isEmpty else { return nil }
            return SimilarOperationApprovalRule(
                toolName: normalizedToolName,
                inputSignature: shellInputSignature(
                    command: trimmedCommand,
                    toolInput: toolInput
                )
            )
        }

        guard let toolInput,
              JSONSerialization.isValidJSONObject(toolInput.mapValues(\.value)),
              let data = try? JSONSerialization.data(
                withJSONObject: toolInput.mapValues(\.value),
                options: [.sortedKeys]
              ),
              let signature = String(data: data, encoding: .utf8) else {
            return nil
        }

        return SimilarOperationApprovalRule(
            toolName: normalizedToolName,
            inputSignature: signature
        )
    }

    /// Codex models reusable command approvals as token prefixes. PermissionRequest
    /// hooks do not currently expose Codex's proposed exec-policy amendment, so
    /// honor it when a compatible bridge provides one and otherwise infer only
    /// narrowly scoped operation prefixes that are safe to recognize locally.
    private nonisolated static func shellInputSignature(
        command: String,
        toolInput: [String: AnyCodable]?
    ) -> String {
        guard let commandTokens = tokenizeSimpleShellCommand(command) else {
            return exactCommandSignature(command)
        }

        if let explicitPrefix = explicitPrefixRule(from: toolInput),
           commandTokens.starts(with: explicitPrefix) {
            return prefixSignature(explicitPrefix)
        }

        if let gitPrefix = gitOperationPrefix(from: commandTokens) {
            return prefixSignature(gitPrefix)
        }

        if let operationPrefix = commandAndFirstArgumentPrefix(from: commandTokens) {
            return prefixSignature(operationPrefix)
        }

        return exactCommandSignature(command)
    }

    private nonisolated static func explicitPrefixRule(
        from toolInput: [String: AnyCodable]?
    ) -> [String]? {
        let value = toolInput?["prefix_rule"]?.value
            ?? toolInput?["prefixRule"]?.value
        if let tokens = value as? [String], !tokens.isEmpty {
            return tokens
        }
        if let values = value as? [Any] {
            let tokens = values.compactMap { $0 as? String }
            if tokens.count == values.count, !tokens.isEmpty {
                return tokens
            }
        }
        return nil
    }

    /// Treat a Git subcommand as the operation boundary. This makes
    /// `git add first` and `git add second` equivalent without allowing an
    /// approval for `git add` to cover destructive operations such as reset.
    private nonisolated static func gitOperationPrefix(
        from tokens: [String]
    ) -> [String]? {
        guard let executable = tokens.first,
              URL(fileURLWithPath: executable).lastPathComponent.lowercased() == "git" else {
            return nil
        }

        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                index += 1
                break
            }
            if gitGlobalOptionsWithSeparateValue.contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return ["git", token.lowercased()]
        }

        guard index < tokens.count else { return nil }
        return ["git", tokens[index].lowercased()]
    }

    /// The local fallback mirrors the operation identity visible to users:
    /// tool name (stored separately) + executable + first argument. Avoid
    /// collapsing shell interpreter wrappers because `bash -lc <script>`,
    /// for example, can represent unrelated operations behind the same prefix.
    private nonisolated static func commandAndFirstArgumentPrefix(
        from tokens: [String]
    ) -> [String]? {
        guard let executable = tokens.first else { return nil }
        let normalizedExecutable =
            URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        guard !normalizedExecutable.isEmpty else { return nil }

        let shellInterpreters: Set<String> = [
            "bash", "dash", "fish", "sh", "zsh"
        ]
        if shellInterpreters.contains(normalizedExecutable) {
            return nil
        }

        guard tokens.count > 1 else {
            return [normalizedExecutable]
        }
        return [normalizedExecutable, tokens[1]]
    }

    private nonisolated static let gitGlobalOptionsWithSeparateValue: Set<String> = [
        "-C",
        "-c",
        "--config-env",
        "--exec-path",
        "--git-dir",
        "--namespace",
        "--super-prefix",
        "--work-tree"
    ]

    private nonisolated static func exactCommandSignature(_ command: String) -> String {
        "exact:\(command)"
    }

    private nonisolated static func prefixSignature(_ tokens: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: tokens),
              let json = String(data: data, encoding: .utf8) else {
            return "prefix:\(tokens.joined(separator: "\u{1F}"))"
        }
        return "prefix:\(json)"
    }

    /// Tokenizes one simple shell command. Compound commands and expansions
    /// deliberately return nil so they keep exact-command matching.
    private nonisolated static func tokenizeSimpleShellCommand(
        _ command: String
    ) -> [String]? {
        enum Quote {
            case single
            case double
        }

        var tokens: [String] = []
        var current = ""
        var quote: Quote?
        var escaped = false

        func finishToken() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        for character in command {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            switch quote {
            case .single:
                if character == "'" {
                    quote = nil
                } else {
                    current.append(character)
                }
            case .double:
                if character == "\"" {
                    quote = nil
                } else if character == "\\" {
                    escaped = true
                } else if character == "`" || character == "$" {
                    return nil
                } else {
                    current.append(character)
                }
            case nil:
                if character == "'" {
                    quote = .single
                } else if character == "\"" {
                    quote = .double
                } else if character == "\\" {
                    escaped = true
                } else if character.isWhitespace {
                    finishToken()
                } else if ";|&<>()`$".contains(character) {
                    return nil
                } else {
                    current.append(character)
                }
            }
        }

        guard quote == nil, !escaped else { return nil }
        finishToken()
        return tokens.isEmpty ? nil : tokens
    }
}

actor SimilarOperationApprovalStore {
    static let shared = SimilarOperationApprovalStore()

    private let maximumSessions = 64
    private let maximumRulesPerSession = 32
    private var rulesBySessionID: [String: [SimilarOperationApprovalRule]] = [:]

    private nonisolated func canonicalSessionID(_ sessionID: String) -> String {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = trimmed.firstIndex(of: ":") {
            let prefix = trimmed[..<separator].lowercased()
            if prefix == "codex" || prefix == "claude" || prefix == "trae" || prefix == "antigravity" {
                return String(trimmed[trimmed.index(after: separator)...])
            }
        }
        return trimmed
    }

    func allow(_ rule: SimilarOperationApprovalRule, forSessionID sessionID: String) {
        let key = canonicalSessionID(sessionID)
        var rules = rulesBySessionID[key] ?? []
        guard !rules.contains(rule) else { return }

        if rules.count >= maximumRulesPerSession {
            rules.removeFirst()
        }
        rules.append(rule)

        if rulesBySessionID[key] == nil,
           rulesBySessionID.count >= maximumSessions,
           let oldestSessionID = rulesBySessionID.keys.first {
            rulesBySessionID.removeValue(forKey: oldestSessionID)
        }
        rulesBySessionID[key] = rules
    }

    func allows(_ rule: SimilarOperationApprovalRule, forSessionID sessionID: String) -> Bool {
        rulesBySessionID[canonicalSessionID(sessionID)]?.contains(rule) == true
    }

    func removeRules(forSessionID sessionID: String) {
        rulesBySessionID.removeValue(forKey: canonicalSessionID(sessionID))
    }
}

extension HookEvent {
    nonisolated var similarOperationApprovalRule: SimilarOperationApprovalRule? {
        // Codex can label a PermissionRequest with a transient status while
        // the hook socket is still waiting for the response. The event type,
        // tool and input are sufficient to identify a reusable operation.
        guard event == "PermissionRequest" else {
            return nil
        }
        return SimilarOperationApprovalRule.make(
            provider: provider,
            toolName: tool,
            toolInput: toolInput
        )
    }
}
