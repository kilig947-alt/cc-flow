import XCTest
@testable import CC_FLOW

final class AntigravityIntegrationTests: XCTestCase {
    func testUsageParserReadsModelQuotaAndMonthlyCredits() throws {
        let capturedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-23T12:00:00Z")
        )
        let data = try JSONSerialization.data(withJSONObject: [
            "userStatus": [
                "cascadeModelConfigData": [
                    "clientModelConfigs": [[
                        "model": "gemini-3-pro",
                        "label": "Gemini 3 Pro",
                        "quotaInfo": [
                            "remainingFraction": 0.73,
                            "resetTime": "2026-07-23T13:00:00Z"
                        ]
                    ]]
                ],
                "planStatus": [
                    "planInfo": ["monthlyPromptCredits": 1_000],
                    "availablePromptCredits": 250
                ]
            ]
        ])

        let result = try XCTUnwrap(
            AntigravityUsageClient.parseStatus(data: data, capturedAt: capturedAt)
        )

        XCTAssertEqual(result.capturedAt, capturedAt)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].id, "antigravity-gemini-five-hour")
        XCTAssertEqual(result.windows[0].label, "Gemini Models · 5 小时限额")
        XCTAssertEqual(result.windows[0].usedPercentage, 27, accuracy: 0.001)
        XCTAssertNotNil(result.windows[0].resetsAt)
    }

    func testHookInstallerPreservesOtherNamedGroups() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "user-linter": [
                "enabled": true,
                "PreToolUse": [[
                    "matcher": "*",
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/local/bin/lint-hook"
                    ]]
                ]]
            ]
        ])
        let profile = try XCTUnwrap(
            ClientProfileRegistry.managedHookProfile(id: "antigravity-hooks")
        )

        let installedData = HookInstaller.updatedAntigravityHookConfigurationData(
            existingData: existing,
            profile: profile
        )
        let installed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: installedData) as? [String: Any]
        )

        XCTAssertNotNil(installed["user-linter"])
        let group = try XCTUnwrap(installed["cc-flow"] as? [String: Any])
        XCTAssertEqual(group["enabled"] as? Bool, true)
        let preToolUse = try XCTUnwrap(group["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.first?["matcher"] as? String, "*")
        let wrappedHooks = try XCTUnwrap(preToolUse.first?["hooks"] as? [[String: Any]])
        XCTAssertTrue(
            (wrappedHooks.first?["command"] as? String)?.contains("--source antigravity") == true
        )
        let preInvocation = try XCTUnwrap(group["PreInvocation"] as? [[String: Any]])
        XCTAssertTrue(
            (preInvocation.first?["command"] as? String)?.contains("--source antigravity") == true
        )

        let removedData = HookInstaller.removingManagedAntigravityHookConfigurationData(
            existingData: installedData
        )
        let removed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: removedData) as? [String: Any]
        )
        XCTAssertNil(removed["cc-flow"])
        XCTAssertNotNil(removed["user-linter"])
    }

    func testAntigravityTranscriptParsing() async throws {
        let sessionId = "antigravity-parser-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-parser-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("\(sessionId).jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let transcript = """
        {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-07-31T04:31:35Z","content":"hello world"}
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-07-31T04:31:37Z","thinking":"let me think","tool_calls":[{"name":"list_dir","args":{"DirectoryPath":"/tmp"}}]}
        {"step_index":2,"source":"MODEL","type":"LIST_DIRECTORY","status":"DONE","created_at":"2026-07-31T04:31:38Z","content":"file1\\nfile2"}
        """
        try transcript.write(to: fileURL, atomically: true, encoding: .utf8)

        let messages = await ConversationParser.shared.parseFullConversation(
            sessionId: sessionId,
            cwd: "/tmp",
            explicitFilePath: fileURL.path
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        if case .text(let text) = messages[0].content.first {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("Expected text block")
        }

        XCTAssertEqual(messages[1].role, .assistant)
        if case .thinking(let thinking) = messages[1].content[0] {
            XCTAssertEqual(thinking, "let me think")
        } else {
            XCTFail("Expected thinking block")
        }

        if case .toolUse(let toolUse) = messages[1].content[1] {
            XCTAssertEqual(toolUse.name, "list_dir")
            XCTAssertEqual(toolUse.input["DirectoryPath"], "/tmp")
            
            let results = await ConversationParser.shared.toolResults(for: sessionId)
            XCTAssertEqual(results[toolUse.id]?.content, "file1\nfile2")
        } else {
            XCTFail("Expected tool use block")
        }

        let info = await ConversationParser.shared.parse(
            sessionId: sessionId,
            cwd: "/tmp",
            explicitFilePath: fileURL.path
        )
        XCTAssertEqual(info.firstUserMessage, "hello world")
        XCTAssertEqual(info.lastMessage, "let me think")
    }
}
