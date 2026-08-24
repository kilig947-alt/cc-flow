import Foundation
import XCTest
@testable import CC_FLOW

final class HookSocketServerClientInfoTests: XCTestCase {
    func testDecodesClaudeCodexOpenCodeAndTraeProvidersWithoutCollapsingThem() throws {
        let cases: [(String, SessionProvider, SessionClientKind)] = [
            ("claude", .claude, .claudeCode),
            ("codex", .codex, .codex),
            ("opencode", .opencode, .opencode),
            ("trae", .trae, .trae)
        ]

        for (provider, expectedProvider, expectedKind) in cases {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString,
                "provider": provider,
                "eventType": "SessionStart",
                "sessionKey": "\(provider):same-id",
                "status": ["kind": "thinking"],
                "metadata": ["session_id": "same-id"]
            ])

            let event = try HookSocketServer.decodeBridgeEventForTesting(data)
            XCTAssertEqual(event.provider, expectedProvider)
            XCTAssertEqual(event.clientInfo.kind, expectedKind)
            XCTAssertEqual(event.sessionId, "\(provider):same-id")
        }
    }

    func testTerminalHostBundlePrefersStandaloneTerminalOverIDEHint() {
        XCTAssertEqual(
            HookSocketServer.resolvedTerminalHostBundleIdentifier(
                terminalBundleID: "com.googlecode.iterm2",
                ideBundleID: "com.trae.app"
            ),
            "com.googlecode.iterm2"
        )
    }

    func testTerminalHostBundleKeepsIDEWhenTerminalIsIDEHost() {
        XCTAssertEqual(
            HookSocketServer.resolvedTerminalHostBundleIdentifier(
                terminalBundleID: "com.trae.app",
                ideBundleID: "com.trae.app"
            ),
            "com.trae.app"
        )
    }

    func testTraeVariantFallsBackToManagedProfileIdentityWithoutIDEBundle() throws {
        let cases: [(name: String, originator: String, bundleID: String)] = [
            ("Trae CN", "Trae CN", "cn.trae.app"),
            ("TRAE Work", "TRAE SOLO", "com.trae.solo.app"),
            ("TRAE Work CN", "TRAE SOLO CN", "cn.trae.solo.app"),
        ]

        for item in cases {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString,
                "provider": "trae",
                "eventType": "SessionStart",
                "sessionKey": "trae:\(UUID().uuidString)",
                "metadata": [
                    "client_kind": "trae",
                    "client_name": item.name,
                    "client_originator": item.originator,
                ],
            ])

            let event = try HookSocketServer.decodeBridgeEventForTesting(data)
            XCTAssertEqual(event.clientInfo.bundleIdentifier, item.bundleID, item.name)
        }
    }

    func testOpenCodeMessageMetadataPreservesAssistantRoleAndMessageID() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString,
            "provider": "opencode",
            "eventType": "message.part.updated",
            "sessionKey": "opencode:session-1",
            "preview": "选哪个？",
            "status": ["kind": "active"],
            "metadata": [
                "session_id": "session-1",
                "message_id": "message-1",
                "message_role": "assistant",
            ],
        ])

        let event = try HookSocketServer.decodeBridgeEventForTesting(data)

        XCTAssertEqual(event.message, "选哪个？")
        XCTAssertEqual(event.messageId, "message-1")
        XCTAssertEqual(event.messageRole, "assistant")
    }
}
