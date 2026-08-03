import XCTest
@testable import CC_FLOW

final class SimilarOperationApprovalRuleTests: XCTestCase {
    func testCodexBashRuleMatchesTheSameFullCommand() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("xcodebuild -project CCFlow.xcodeproj test")]
        )
        let repeated = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("  xcodebuild -project CCFlow.xcodeproj test\n")]
        )

        XCTAssertEqual(first, repeated)
    }

    func testCodexNonGitRuleMatchesWhenCommandAndFirstArgumentMatch() {
        let debugBuild = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("xcodebuild -configuration Debug build")]
        )
        let releaseBuild = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("xcodebuild -configuration Release build")]
        )

        XCTAssertEqual(debugBuild, releaseBuild)
    }

    func testCodexNonGitRuleKeepsDifferentFirstArgumentsSeparate() {
        let build = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("swift build --configuration debug")]
        )
        let test = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("swift test --filter ExampleTests")]
        )

        XCTAssertNotEqual(build, test)
    }

    func testShellInterpreterWrapperFallsBackToExactMatching() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("bash -lc 'git add First.swift'")]
        )
        let second = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("bash -lc 'git add Second.swift'")]
        )

        XCTAssertNotEqual(first, second)
    }

    func testCodexGitRuleMatchesDifferentArgumentsForSameSubcommand() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git add Sources/First.swift")]
        )
        let second = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("/usr/bin/git add Sources/Second.swift")]
        )

        XCTAssertEqual(first, second)
    }

    func testCodexGitRuleKeepsDifferentSubcommandsSeparate() {
        let add = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git add Sources/First.swift")]
        )
        let reset = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git reset --hard")]
        )

        XCTAssertNotEqual(add, reset)
    }

    func testCodexGitRuleIgnoresGlobalOptionsWhenFindingSubcommand() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Shell",
            toolInput: ["command": AnyCodable("git -C first-repo add First.swift")]
        )
        let second = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Shell",
            toolInput: ["command": AnyCodable("git -C second-repo add Second.swift")]
        )

        XCTAssertEqual(first, second)
    }

    func testCompoundGitCommandFallsBackToExactMatching() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git add First.swift && echo first")]
        )
        let second = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git add Second.swift && echo second")]
        )

        XCTAssertNotEqual(first, second)
    }

    func testExplicitPrefixRuleMatchesDifferentArguments() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: [
                "command": AnyCodable("cargo install cargo-insta"),
                "prefix_rule": AnyCodable(["cargo", "install"])
            ]
        )
        let second = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Bash",
            toolInput: [
                "command": AnyCodable("cargo install ripgrep"),
                "prefix_rule": AnyCodable(["cargo", "install"])
            ]
        )

        XCTAssertEqual(first, second)
    }

    func testNonBashRuleUsesStableSortedJSONInput() {
        let first = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Write",
            toolInput: [
                "path": AnyCodable("/tmp/example"),
                "content": AnyCodable("hello")
            ]
        )
        let reordered = SimilarOperationApprovalRule.make(
            provider: .codex,
            toolName: "Write",
            toolInput: [
                "content": AnyCodable("hello"),
                "path": AnyCodable("/tmp/example")
            ]
        )

        XCTAssertEqual(first, reordered)
    }

    func testRuleIsOnlyAvailableForCodex() {
        XCTAssertNil(
            SimilarOperationApprovalRule.make(
                provider: .claude,
                toolName: "Bash",
                toolInput: ["command": AnyCodable("swift test")]
            )
        )
    }

    func testStoreScopesAllowedOperationToOneSession() async {
        let store = SimilarOperationApprovalStore()
        let rule = SimilarOperationApprovalRule(
            toolName: "bash",
            inputSignature: "swift test"
        )

        await store.allow(rule, forSessionID: "session-a")

        let allowedInOriginalSession = await store.allows(rule, forSessionID: "session-a")
        let allowedInDifferentSession = await store.allows(rule, forSessionID: "session-b")
        XCTAssertTrue(allowedInOriginalSession)
        XCTAssertFalse(allowedInDifferentSession)
    }
}
