import XCTest
@testable import CC_FLOW

final class TerminalAppRegistryTests: XCTestCase {
    func testInfersITermBundleIdentifierFromHelperCommand() {
        XCTAssertEqual(
            TerminalAppRegistry.inferredBundleIdentifier(
                forCommand: "/Users/example/Library/Application Support/iTerm2/iTermServer-3.6.9 socket"
            ),
            "com.googlecode.iterm2"
        )
    }
}
