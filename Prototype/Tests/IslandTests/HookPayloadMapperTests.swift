import Foundation
import IslandShared
import Testing

@Test
func mapsOpenCodeQuestionAndFormatsAnswerResponse() throws {
    let payload = #"{"hook_event_name":"PreToolUse","opencode_event_type":"question.asked","session_id":"ses_open","cwd":"/tmp/project","tool_name":"AskUserQuestion","questions":[{"header":"Choice","question":"Pick one","options":[{"label":"A","description":"first"},{"label":"B","description":"second"}]}],"tool_input":{"questions":[{"question":"Pick one"}]}}"#.data(using: .utf8)!
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .opencode,
        arguments: ["bridge", "--source", "opencode", "--client-kind", "opencode"],
        environment: [:],
        stdinData: payload
    )

    #expect(envelope.sessionKey == "opencode:ses_open")
    #expect(envelope.status?.kind == .waitingForInput)
    #expect(envelope.intervention?.kind == .question)
    #expect(envelope.intervention?.options.map(\.title) == ["A", "B"])
    #expect(envelope.expectsResponse)

    let output = HookPayloadMapper.stdoutPayload(
        for: .opencode,
        response: BridgeResponse(requestID: UUID(), decision: .answer(["Pick one": "B"])),
        eventType: "question.asked",
        metadata: [:]
    )
    let json = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    #expect((json["answers"] as? [String: String])?["Pick one"] == "B")
}

@Test
func mapsApprovalEventFromHookPayload() throws {
    let payload = """
    {
      "hook_event_name": "PermissionRequest",
      "tool_name": "Bash",
      "reason": "Needs to run tests",
      "session_id": "abc123"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["cc-flow-bridge", "--source", "trae"],
        environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "iterm-1", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.provider == .trae)
    #expect(envelope.eventType == "PermissionRequest")
    #expect(envelope.intervention?.kind == .approval)
    #expect(envelope.status?.kind == .waitingForApproval)
    #expect(envelope.sessionKey == "trae:abc123")
}

@Test
func namespacesIdenticalSessionIDsByProvider() throws {
    let payload = #"{"hook_event_name":"SessionStart","session_id":"shared-id"}"#.data(using: .utf8)!
    let environment = ["PWD": "/tmp/demo"]

    let claude = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: environment,
        stdinData: payload
    )
    let codex = HookPayloadMapper.makeEnvelope(
        source: .codex,
        arguments: ["cc-flow-bridge", "--source", "codex"],
        environment: environment,
        stdinData: payload
    )
    let trae = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["cc-flow-bridge", "--source", "trae"],
        environment: environment,
        stdinData: payload
    )

    #expect(claude.sessionKey == "claude:shared-id")
    #expect(codex.sessionKey == "codex:shared-id")
    #expect(trae.sessionKey == "trae:shared-id")
}

@Test
func routePromptsToTerminalDropsApprovalIntervention() throws {
    let payload = """
    {
      "hook_event_name": "PermissionRequest",
      "tool_name": "Bash",
      "reason": "Needs to run tests",
      "session_id": "abc123"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload,
        runtimeConfig: BridgeRuntimeConfig(routePromptsToTerminal: true)
    )

    #expect(envelope.intervention == nil)
    #expect(envelope.expectsResponse == false)
}

@Test
func routePromptsToTerminalDropsAskUserQuestionIntervention() throws {
    let payload = """
    {
      "hook_event_name": "PreToolUse",
      "tool_name": "AskUserQuestion",
      "tool_input": {
        "questions": [
          {"id": "q1", "question": "Pick one", "options": ["A", "B"]}
        ]
      },
      "session_id": "abc123"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload,
        runtimeConfig: BridgeRuntimeConfig(routePromptsToTerminal: true)
    )

    #expect(envelope.intervention == nil)
    #expect(envelope.expectsResponse == false)
}

@Test
func bridgeRuntimeConfigLoadsFromEnvironmentPath() async throws {
    try await withTemporaryDirectory { directory in
        let configURL = directory.appending(path: "bridge-config.json")
        try """
        {
          "routePromptsToTerminal": true
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = BridgeRuntimeConfig.load(
            environment: [BridgeRuntimeConfig.configPathEnvironmentKey: configURL.path()]
        )

        #expect(config.routePromptsToTerminal)
    }
}

@Test
func bridgeRuntimeConfigUsesCCFlowPathAndEnvironmentFallbackOrder() async throws {
    try await withTemporaryDirectory { directory in
        let ccURL = directory.appending(path: "cc.json")
        let traeURL = directory.appending(path: "trae.json")
        let islandURL = directory.appending(path: "island.json")
        try #"{"routePromptsToTerminal":true}"#.write(to: ccURL, atomically: true, encoding: .utf8)
        try #"{"routePromptsToTerminal":false}"#.write(to: traeURL, atomically: true, encoding: .utf8)
        try #"{"routePromptsToTerminal":false}"#.write(to: islandURL, atomically: true, encoding: .utf8)

        #expect(BridgeRuntimeConfig.relativeConfigPath == ".cc-flow/bridge-config.json")
        #expect(BridgeRuntimeConfig.configuredURL(environment: [
            "CC_FLOW_BRIDGE_CONFIG": ccURL.path(),
            "TRAE_FLOW_BRIDGE_CONFIG": traeURL.path(),
            "ISLAND_BRIDGE_CONFIG": islandURL.path()
        ]) == ccURL)
        #expect(BridgeRuntimeConfig.configuredURL(environment: [
            "TRAE_FLOW_BRIDGE_CONFIG": traeURL.path(),
            "ISLAND_BRIDGE_CONFIG": islandURL.path()
        ]) == traeURL)
        #expect(BridgeRuntimeConfig.configuredURL(environment: [
            "ISLAND_BRIDGE_CONFIG": islandURL.path()
        ]) == islandURL)
    }
}

@Test
func bridgeRuntimeConfigLoadedFromEnvironmentDropsApprovalIntervention() async throws {
    try await withTemporaryDirectory { directory in
        let configURL = directory.appending(path: "bridge-config.json")
        try """
        {
          "routePromptsToTerminal": true
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let environment = [
            BridgeRuntimeConfig.configPathEnvironmentKey: configURL.path(),
            "TERM_PROGRAM": "iTerm.app",
            "PWD": "/tmp/demo"
        ]
        let payload = """
        {
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "reason": "Needs to run tests",
          "session_id": "abc123"
        }
        """.data(using: .utf8)!

        let envelope = HookPayloadMapper.makeEnvelope(
            source: .trae,
            arguments: ["island-bridge", "--source", "trae"],
            environment: environment,
            stdinData: payload,
            runtimeConfig: BridgeRuntimeConfig.load(environment: environment)
        )

        #expect(envelope.intervention == nil)
        #expect(envelope.expectsResponse == false)
        #expect(envelope.metadata["suppress_in_app_prompt"] == "true")
    }
}

@Test
func mapsGhosttyTerminalContextFromEnvironment() throws {
    let payload = """
    {
      "hook_event_name": "UserPromptSubmit",
      "session_id": "ghostty-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: [
            "TERM_PROGRAM": "ghostty",
            "TERM_SESSION_ID": "ghostty-terminal-1",
            "PWD": "/tmp/demo"
        ],
        stdinData: payload
    )

    #expect(envelope.terminalContext.terminalProgram == "ghostty")
    #expect(envelope.terminalContext.terminalBundleID == "com.mitchellh.ghostty")
    #expect(envelope.terminalContext.terminalSessionID == "ghostty-terminal-1")
}

@Test
func mapsCmuxTerminalContextFromEnvironment() throws {
    let payload = """
    {
      "hook_event_name": "UserPromptSubmit",
      "session_id": "cmux-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: [
            "TERM_PROGRAM": "cmux",
            "TERM_SESSION_ID": "65a2028f-a93c-48e0-b46a-3f4c20c94b81",
            "PWD": "/tmp/demo"
        ],
        stdinData: payload
    )

    #expect(envelope.terminalContext.terminalProgram == "cmux")
    #expect(envelope.terminalContext.terminalBundleID == "com.cmuxterm.app")
    #expect(envelope.terminalContext.terminalSessionID == "65a2028f-a93c-48e0-b46a-3f4c20c94b81")
}

@Test
func mapsWezTermTerminalContextFromEnvironment() throws {
    let payload = """
    {
      "hook_event_name": "UserPromptSubmit",
      "session_id": "wezterm-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["TERM_PROGRAM": "WezTerm", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.terminalContext.terminalProgram == "WezTerm")
    #expect(envelope.terminalContext.terminalBundleID == "com.github.wez.wezterm")
}

@Test
func mapsSSHRemoteHostFromHostnameEnvironmentBeforeConnectionIP() throws {
    let payload = """
    {
      "hook_event_name": "UserPromptSubmit",
      "session_id": "ssh-hostname-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: [
            "SSH_CONNECTION": "192.168.1.2 49822 10.0.0.10 22",
            "HOSTNAME": "devbox",
            "PWD": "/tmp/demo"
        ],
        stdinData: payload
    )

    #expect(envelope.terminalContext.transport == "ssh")
    #expect(envelope.terminalContext.remoteHost == "devbox")
    #expect(envelope.metadata["remote_host"] == "devbox")
}

@Test
func mapsQuestionEventOptions() throws {
    let payload = """
    {
      "questions": [{
        "id": "terminal_scope",
        "question": "Which terminal?",
        "options": [
          {"label": "iTerm2", "description": "Primary recommendation"},
          {"label": "Terminal", "description": "Fallback"}
        ]
      }]
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.intervention?.kind == .question)
    #expect(envelope.intervention?.options.count == 2)
    #expect(envelope.status?.kind == .waitingForInput)
}

@Test
func claudePermissionPayloadUsesHookSpecificOutput() throws {
    let payload = HookPayloadMapper.stdoutPayload(
        for: .claude,
        response: BridgeResponse(requestID: UUID(), decision: .approve),
        eventType: "PermissionRequest",
        metadata: [:]
    )
    let json = try #require(
        JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
    )
    let hookSpecificOutput = try #require(json["hookSpecificOutput"] as? [String: Any])
    #expect(hookSpecificOutput["hookEventName"] as? String == "PermissionRequest")
    let decision = try #require(hookSpecificOutput["decision"] as? [String: Any])
    #expect(decision["behavior"] as? String == "allow")
}

@Test
func codexPermissionPayloadUsesOfficialDecisionShape() throws {
    let allowPayload = HookPayloadMapper.stdoutPayload(
        for: .codex,
        response: BridgeResponse(requestID: UUID(), decision: .approveForSession),
        eventType: "PermissionRequest",
        metadata: [:]
    )
    let allowJSON = try #require(JSONSerialization.jsonObject(with: Data(allowPayload.utf8)) as? [String: Any])
    let allowOutput = try #require(allowJSON["hookSpecificOutput"] as? [String: Any])
    let allowDecision = try #require(allowOutput["decision"] as? [String: Any])
    #expect(allowOutput["hookEventName"] as? String == "PermissionRequest")
    #expect(allowDecision["behavior"] as? String == "allow")

    let denyPayload = HookPayloadMapper.stdoutPayload(
        for: .codex,
        response: BridgeResponse(requestID: UUID(), decision: .deny),
        eventType: "PermissionRequest",
        metadata: [:]
    )
    let denyJSON = try #require(JSONSerialization.jsonObject(with: Data(denyPayload.utf8)) as? [String: Any])
    let denyOutput = try #require(denyJSON["hookSpecificOutput"] as? [String: Any])
    let denyDecision = try #require(denyOutput["decision"] as? [String: Any])
    #expect(denyDecision["behavior"] as? String == "deny")
}

@Test
func codexQuestionAnswerDoesNotPretendToSupportGenericInput() {
    let payload = HookPayloadMapper.stdoutPayload(
        for: .codex,
        response: BridgeResponse(requestID: UUID(), decision: .answer(["answer": "A"])),
        eventType: "UserInputRequest",
        metadata: [:]
    )

    #expect(payload == "{}")
}

@Test
func codexStopWaitsForNativeNotificationContinuation() {
    let payload = #"{"hook_event_name":"Stop","session_id":"codex-stop","last_assistant_message":"请选择？"}"#.data(using: .utf8)!
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .codex,
        arguments: ["cc-flow-bridge", "--source", "codex", "--client-kind", "codex"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.expectsResponse)
}

@Test
func codexStopPreservesMultilineAssistantMessageForOptionParsing() {
    let message = """
    结果放在哪里？

    A. 统一任务中心
    B. 新建对话
    C. 原对话
    """
    let payload = try! JSONSerialization.data(withJSONObject: [
        "hook_event_name": "Stop",
        "session_id": "codex-stop-options",
        "last_assistant_message": message
    ])
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .codex,
        arguments: ["cc-flow-bridge", "--source", "codex", "--client-kind", "codex"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.metadata["last_assistant_message"] == message)
    #expect(envelope.preview == "结果放在哪里？ A. 统一任务中心 B. 新建对话 C. 原对话")
}

@Test
func codexStopDoesNotWaitWhenPromptsRouteToTerminal() {
    let payload = #"{"hook_event_name":"Stop","session_id":"codex-stop","last_assistant_message":"请选择？"}"#.data(using: .utf8)!
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .codex,
        arguments: ["cc-flow-bridge", "--source", "codex", "--client-kind", "codex"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload,
        runtimeConfig: BridgeRuntimeConfig(routePromptsToTerminal: true)
    )

    #expect(envelope.expectsResponse == false)
}

@Test
func codexStopAnswerUsesNativeBlockContinuation() throws {
    let payload = HookPayloadMapper.stdoutPayload(
        for: .codex,
        response: BridgeResponse(
            requestID: UUID(),
            decision: .answer(["answer": "C"]),
            reason: "选择 C，两者结合"
        ),
        eventType: "Stop",
        metadata: [:]
    )
    let json = try #require(
        JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
    )

    #expect(json["decision"] as? String == "block")
    #expect(json["reason"] as? String == "选择 C，两者结合")
}

@Test
func codexQuestionPayloadDoesNotCreateBlockingIntervention() {
    let payload = #"{"hook_event_name":"PreToolUse","session_id":"codex-question","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick","options":["A","B"]}]}}"#.data(using: .utf8)!
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .codex,
        arguments: ["cc-flow-bridge", "--source", "codex", "--client-kind", "codex"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.intervention == nil)
    #expect(envelope.expectsResponse == false)
}

@Test
func claudeQuestionAnswerPayloadPreservesFullUpdatedInputForPermissionRequests() throws {
    let response = BridgeResponse(
        requestID: UUID(),
        decision: .answer([:]),
        updatedInput: [
            "questions": .array([
                .object([
                    "id": .string("terminal_scope"),
                    "question": .string("Which terminal?"),
                    "options": .array([
                        .object(["label": .string("iTerm2")]),
                        .object(["label": .string("Terminal")])
                    ])
                ])
            ]),
            "answers": .object([
                "Which terminal?": .string("iTerm2")
            ])
        ]
    )

    let payload = HookPayloadMapper.stdoutPayload(
        for: .claude,
        response: response,
        eventType: "PermissionRequest",
        metadata: [:]
    )

    let json = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    let hookSpecificOutput = try #require(json["hookSpecificOutput"] as? [String: Any])
    let decision = try #require(hookSpecificOutput["decision"] as? [String: Any])
    #expect(decision["behavior"] as? String == "allow")

    let updatedInput = try #require(decision["updatedInput"] as? [String: Any])
    let questions = try #require(updatedInput["questions"] as? [[String: Any]])
    let answers = try #require(updatedInput["answers"] as? [String: String])
    #expect(questions.first?["question"] as? String == "Which terminal?")
    #expect(answers["Which terminal?"] == "iTerm2")
}

@Test
func claudePreToolUseQuestionAnswerUsesOfficialUpdatedInputShape() throws {
    let response = BridgeResponse(
        requestID: UUID(),
        decision: .answer([:]),
        updatedInput: [
            "questions": .array([
                .object([
                    "question": .string("Which terminal?"),
                    "options": .array([.string("iTerm2"), .string("Terminal")])
                ])
            ]),
            "answers": .object(["Which terminal?": .string("iTerm2")])
        ]
    )

    let payload = HookPayloadMapper.stdoutPayload(
        for: .claude,
        response: response,
        eventType: "PreToolUse",
        metadata: ["tool_name": "AskUserQuestion"]
    )

    let json = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    let output = try #require(json["hookSpecificOutput"] as? [String: Any])
    #expect(output["hookEventName"] as? String == "PreToolUse")
    #expect(output["permissionDecision"] as? String == "allow")
    #expect(output["decision"] == nil)
    let updatedInput = try #require(output["updatedInput"] as? [String: Any])
    let answers = try #require(updatedInput["answers"] as? [String: String])
    #expect(answers["Which terminal?"] == "iTerm2")
}

@Test
func bridgeAnswerPayloadExtractsNestedAnswersForRemoteQuestionResponses() {
    let extracted = BridgeAnswerPayload.extractAnswers(from: [
        "questions": .array([
            .object([
                "id": .string("terminal_scope"),
                "question": .string("Which terminal?")
            ])
        ]),
        "answers": .object([
            "Which terminal?": .string("iTerm2"),
            "selection_index": .int(1),
            "confirmed": .bool(true),
            "choices": .array([
                .string("iTerm2"),
                .string("Terminal")
            ])
        ])
    ])

    #expect(extracted["Which terminal?"] == "iTerm2")
    #expect(extracted["selection_index"] == "1")
    #expect(extracted["confirmed"] == "true")
    #expect(extracted["choices"] == "iTerm2, Terminal")
}

@Test
func claudeUserInputAnswerPayloadPreservesFullUpdatedInput() throws {
    let response = BridgeResponse(
        requestID: UUID(),
        decision: .answer([:]),
        updatedInput: [
            "questions": .array([
                .object([
                    "question": .string("Which terminal?")
                ])
            ]),
            "answers": .object([
                "Which terminal?": .string("iTerm2")
            ])
        ]
    )

    let payload = HookPayloadMapper.stdoutPayload(
        for: .claude,
        response: response,
        eventType: "UserInputRequest",
        metadata: [:]
    )

    let json = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    let hookSpecificOutput = try #require(json["hookSpecificOutput"] as? [String: Any])
    #expect(hookSpecificOutput["permissionDecision"] as? String == "allow")

    let updatedInput = try #require(hookSpecificOutput["updatedInput"] as? [String: Any])
    let questions = try #require(updatedInput["questions"] as? [[String: Any]])
    let answers = try #require(updatedInput["answers"] as? [String: String])
    #expect(questions.first?["question"] as? String == "Which terminal?")
    #expect(answers["Which terminal?"] == "iTerm2")
}

@Test
func claudeNonQuestionAnswerPayloadKeepsLegacyFlattenedShape() throws {
    let response = BridgeResponse(
        requestID: UUID(),
        decision: .answer([
            "terminal_scope": "iTerm2"
        ]),
        updatedInput: [
            "answers": .object([
                "terminal_scope": .string("iTerm2")
            ])
        ]
    )

    let payload = HookPayloadMapper.stdoutPayload(
        for: .claude,
        response: response,
        eventType: "PermissionRequest",
        metadata: ["tool_name": "Bash"]
    )

    let json = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    let hookSpecificOutput = try #require(json["hookSpecificOutput"] as? [String: Any])
    let decision = try #require(hookSpecificOutput["decision"] as? [String: Any])
    let updatedInput = try #require(decision["updatedInput"] as? [String: String])
    #expect(updatedInput["terminal_scope"] == "iTerm2")
}

@Test
func previewFallsBackToStructuredToolInput() throws {
    let payload = """
    {
      "hook_event_name": "PreToolUse",
      "tool_name": "Bash",
      "tool_input": {"command": "npm test"},
      "session_id": "abc123"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.preview == #"Bash {"command":"npm test"}"#)
}

@Test
func claudePostToolUseResolvedQuestionDoesNotKeepSocketOpen() throws {
    let payload = """
    {
      "hook_event_name": "PostToolUse",
      "session_id": "claude-resolved-question",
      "tool_name": "AskUserQuestion",
      "tool_input": {
        "questions": [
          {
            "header": "任务",
            "question": "你想先处理哪个部分？",
            "options": [{"label": "SessionStore"}]
          }
        ],
        "answers": {
          "你想先处理哪个部分？": "SessionStore"
        }
      },
      "tool_response": {
        "questions": [
          {
            "header": "任务",
            "question": "你想先处理哪个部分？",
            "options": [{"label": "SessionStore"}]
          }
        ],
        "answers": {
          "你想先处理哪个部分？": "SessionStore"
        }
      },
      "transcript_path": "/tmp/claude-resolved-question.jsonl"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "PostToolUse")
    #expect(envelope.status?.kind == .active)
    #expect(envelope.expectsResponse == false)
    #expect(envelope.intervention == nil)
    #expect(envelope.metadata["tool_response"]?.contains("SessionStore") == true)
}

// MARK: - Stop family mapping (fix-claude-sound-triggers)

@Test
func claudeStopMapsToWaitingForInput() throws {
    let payload = """
    {
      "hook_event_name": "Stop",
      "session_id": "claude-stop-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "Stop")
    #expect(envelope.status?.kind == .waitingForInput)
    #expect(envelope.intervention == nil)
}

@Test
func traeStopMapsToCompleted() throws {
    let payload = #"{"hook_event_name":"Stop","session_id":"trae-stop-1"}"#.data(using: .utf8)!
    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["cc-flow-bridge", "--source", "trae"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.status?.kind == .completed)
}

@Test
func claudeSubagentStopMapsToRunningTool() throws {
    let payload = """
    {
      "hook_event_name": "SubagentStop",
      "session_id": "claude-subagent-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "SubagentStop")
    #expect(envelope.status?.kind == .runningTool)
}

@Test
func claudeSubagentStartMapsToRunningTool() throws {
    let payload = """
    {
      "hook_event_name": "SubagentStart",
      "session_id": "claude-subagent-2"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "SubagentStart")
    #expect(envelope.status?.kind == .runningTool)
}

@Test
func claudeStopFailureMapsToWaitingForInput() throws {
    let payload = """
    {
      "hook_event_name": "StopFailure",
      "session_id": "claude-stopfail-1",
      "error": "rate_limit"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "StopFailure")
    #expect(envelope.status?.kind == .waitingForInput)
}

@Test
func claudeSessionEndMapsToCompleted() throws {
    let payload = """
    {
      "hook_event_name": "SessionEnd",
      "session_id": "claude-end-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .claude,
        arguments: ["cc-flow-bridge", "--source", "claude"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "SessionEnd")
    #expect(envelope.status?.kind == .completed)
}

@Test
func unknownStopVariantFallsBackToCompleted() throws {
    // Conservative default: an unknown stop/end-substring event we have not
    // audited stays mapped to .completed so we don't accumulate ghost sessions.
    let payload = """
    {
      "hook_event_name": "MysteryStopThing",
      "session_id": "claude-mystery-1"
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .trae,
        arguments: ["island-bridge", "--source", "trae"],
        environment: ["TERM_PROGRAM": "iTerm.app", "PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.eventType == "MysteryStopThing")
    #expect(envelope.status?.kind == .completed)
}

@Test
func antigravityCamelCaseToolPayloadMapsToSessionEnvelope() throws {
    let payload = """
    {
      "hook_event_name": "PreToolUse",
      "conversationId": "antigravity-session-1",
      "workspacePaths": ["/tmp/real-project"],
      "transcriptPath": "/tmp/antigravity.jsonl",
      "toolCall": {
        "name": "run_command",
        "args": {"command": "swift test"}
      }
    }
    """.data(using: .utf8)!

    let envelope = HookPayloadMapper.makeEnvelope(
        source: .antigravity,
        arguments: ["cc-flow-bridge", "--source", "antigravity"],
        environment: ["PWD": "/tmp/demo"],
        stdinData: payload
    )

    #expect(envelope.sessionKey == "antigravity:antigravity-session-1")
    #expect(envelope.eventType == "PreToolUse")
    #expect(envelope.cwd == "/tmp/real-project")
    #expect(envelope.title == "run_command")
    #expect(envelope.status?.kind == .runningTool)
}

@Test
func antigravityApprovalUsesNativeDecisionShape() throws {
    let allowPayload = HookPayloadMapper.stdoutPayload(
        for: .antigravity,
        response: BridgeResponse(requestID: UUID(), decision: .approve),
        eventType: "PreToolUse",
        metadata: [:]
    )
    let allowJSON = try #require(
        JSONSerialization.jsonObject(with: Data(allowPayload.utf8)) as? [String: Any]
    )
    #expect(allowJSON["decision"] as? String == "allow")

    let denyPayload = HookPayloadMapper.stdoutPayload(
        for: .antigravity,
        response: BridgeResponse(requestID: UUID(), decision: .deny, reason: "用户拒绝"),
        eventType: "PreToolUse",
        metadata: [:]
    )
    let denyJSON = try #require(
        JSONSerialization.jsonObject(with: Data(denyPayload.utf8)) as? [String: Any]
    )
    #expect(denyJSON["decision"] as? String == "deny")
    #expect(denyJSON["reason"] as? String == "用户拒绝")
}
