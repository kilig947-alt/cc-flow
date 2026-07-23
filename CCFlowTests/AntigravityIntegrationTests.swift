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
}
