import Foundation
import Testing
@testable import CC_FLOW

struct CodexSessionTitleIndexTests {
    @Test
    func codexThreadNameBecomesTheTaskTitleBesideTheProjectName() {
        let session = SessionState(
            sessionId: "codex:thread-1",
            cwd: "/projects/kili-pay-test",
            projectName: "kili-pay-test",
            provider: .codex,
            sessionName: "完善Workflow MCP能力"
        )

        #expect(session.projectName == "kili-pay-test")
        #expect(session.effectiveTaskTitle == "完善Workflow MCP能力")
        #expect(session.displayTitle == "完善Workflow MCP能力")
    }

    @Test
    func readsThreadNameForPrefixedAndRawSessionIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let indexURL = directory.appendingPathComponent("session_index.jsonl")
        try """
        {"id":"thread-1","thread_name":"完善Workflow MCP能力","updated_at":"2026-07-30T04:26:53Z"}

        """.write(to: indexURL, atomically: true, encoding: .utf8)

        var index = CodexSessionTitleIndex(indexURL: indexURL)

        #expect(index.title(for: "thread-1") == "完善Workflow MCP能力")
        #expect(index.title(for: "codex:thread-1") == "完善Workflow MCP能力")
        #expect(index.title(for: "codex:missing") == nil)
    }

    @Test
    func reloadsRenamedThreadsAndUsesLatestEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let indexURL = directory.appendingPathComponent("session_index.jsonl")
        var index = CodexSessionTitleIndex(indexURL: indexURL)

        try """
        {"id":"thread-1","thread_name":"旧标题"}

        """.write(to: indexURL, atomically: true, encoding: .utf8)
        #expect(index.title(for: "codex:thread-1") == "旧标题")

        try """
        {"id":"thread-1","thread_name":"旧标题"}
        {"id":"thread-1","thread_name":"新标题"}

        """.write(to: indexURL, atomically: true, encoding: .utf8)
        #expect(index.title(for: "codex:thread-1") == "新标题")
    }
}
