import XCTest
@testable import CC_FLOW

final class SessionResumeCommandTests: XCTestCase {
    func testCodexCopiesResumeCommand() {
        XCTAssertEqual(
            SessionResumeCommand.clipboardText(
                provider: .codex,
                sessionId: "019fb26f-d997-7f72-9225-71d7bed004a4"
            ),
            "codex resume 019fb26f-d997-7f72-9225-71d7bed004a4"
        )
    }

    func testClaudeCopiesResumeCommand() {
        XCTAssertEqual(
            SessionResumeCommand.clipboardText(
                provider: .claude,
                sessionId: "claude:session-123"
            ),
            "claude --resume session-123"
        )
    }

    func testClientsWithoutPublicResumeCommandCopySessionId() {
        XCTAssertEqual(
            SessionResumeCommand.clipboardText(
                provider: .trae,
                sessionId: "trae-session"
            ),
            "trae-session"
        )
        XCTAssertEqual(
            SessionResumeCommand.clipboardText(
                provider: .antigravity,
                sessionId: "antigravity-session"
            ),
            "antigravity-session"
        )
    }
}
