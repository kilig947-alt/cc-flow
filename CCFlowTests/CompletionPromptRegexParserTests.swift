import XCTest
@testable import CC_FLOW

final class CompletionPromptRegexParserTests: XCTestCase {
    @MainActor
    func testCodexStopSynthesizesQuestionAndDeduplicatesSameCompletion() async throws {
        let sessionID = "completion-regex-stop-\(UUID().uuidString)"
        let store = SessionStore.shared
        let settings = AppSettings.shared
        let originalRules = settings.completionPromptRegexRules
        let originalRouteSetting = settings.routePromptsToTerminal
        settings.completionPromptRegexRules = CompletionPromptRegexRule.defaultTemplates
        settings.routePromptsToTerminal = false
        addTeardownBlock {
            Task { @MainActor in
                settings.completionPromptRegexRules = originalRules
                settings.routePromptsToTerminal = originalRouteSetting
                await store.process(.sessionArchived(sessionId: sessionID))
            }
        }

        let stopEvent = HookEvent(
            sessionId: sessionID,
            cwd: "/tmp/project",
            event: "Stop",
            status: "waiting",
            provider: .codex,
            clientInfo: SessionClientInfo(kind: .codex, name: "Codex"),
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: "bridge-stop-\(sessionID)",
            notificationType: nil,
            message: """
            请选择数据库关系展示方式：
            A. 仅结构关系
            B. 仅知识关系
            C. 两者结合
            """
        )

        await store.process(.hookReceived(stopEvent))
        let firstSnapshot = await store.session(for: sessionID)
        var session = try XCTUnwrap(firstSnapshot)
        XCTAssertEqual(session.phase, .waitingForInput)
        XCTAssertEqual(session.intervention?.metadata["source"], "completionRegex")
        XCTAssertEqual(
            session.intervention?.metadata["responseMode"],
            "stop_hook_continuation"
        )
        XCTAssertEqual(
            session.intervention?.metadata["originalToolUseId"],
            "bridge-stop-\(sessionID)"
        )
        XCTAssertEqual(
            session.intervention?.resolvedQuestions.first?.options.map(\.title),
            ["A. 仅结构关系", "B. 仅知识关系", "C. 两者结合"]
        )

        await store.process(.interventionResolved(
            sessionId: sessionID,
            nextPhase: .processing,
            submittedAnswers: ["completion-regex-question": ["C. 两者结合"]]
        ))
        await store.process(.hookReceived(stopEvent))
        let deduplicatedSnapshot = await store.session(for: sessionID)
        session = try XCTUnwrap(deduplicatedSnapshot)
        XCTAssertNil(session.intervention)
    }

    func testReviewTemplateCreatesFollowUpQuestion() throws {
        let message = """
        设计文档已编写、自检并提交：

        请审阅设计。你确认后，我再进入 writing-plans 阶段生成详细开发计划。
        """

        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(match.intervention.metadata["responseMode"], "follow_up")
        XCTAssertEqual(question.header, "审阅与确认")
        XCTAssertEqual(question.options.map(\.title), ["确认，继续", "需要修改"])
        XCTAssertTrue(question.allowsOther)
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["确认，继续"]]
            ),
            "我已审阅并确认，请继续。"
        )
    }

    func testListedOptionsAreExtractedAndRenderedAsExplicitReply() throws {
        let message = """
        局部关系图希望包含哪些关系？

        A. 仅结构关系：库→表、表间 Join/外键。
        B. 仅知识关系：业务概念、指标、Wiki 页面关联。
        C. 两者结合（推荐）：默认突出结构关系，同时显示少量概念/指标节点。
        """

        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(question.header, "字母或数字选项")
        XCTAssertEqual(question.options.map(\.title), [
            "A. 仅结构关系：库→表、表间 Join/外键。",
            "B. 仅知识关系：业务概念、指标、Wiki 页面关联。",
            "C. 两者结合（推荐）：默认突出结构关系，同时显示少量概念/指标节点。"
        ])
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: [question.options[2].title]]
            ),
            "选择 C：两者结合（推荐）：默认突出结构关系，同时显示少量概念/指标节点。"
        )
    }

    func testCodeFenceOptionsAreIgnored() {
        let message = """
        示例格式如下：
        ```
        A. 第一项
        B. 第二项
        ```
        已完成。
        """

        XCTAssertNil(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
    }

    func testInvalidRegexIsSkippedAndReported() {
        let rule = CompletionPromptRegexRule(
            name: "Invalid",
            triggerPattern: "(",
            staticOptions: [
                CompletionPromptStaticOption(title: "是", reply: "是"),
                CompletionPromptStaticOption(title: "否", reply: "否")
            ]
        )

        XCTAssertNotNil(CompletionPromptRegexParser.validationError(for: rule.triggerPattern))
        XCTAssertNil(CompletionPromptRegexParser.match(message: "任意内容", rules: [rule]))
    }

    func testFreeformAnswerPassesThroughUnchanged() throws {
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "请审阅设计。你确认后我再继续。",
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["请先补充失败回滚方案。"]]
            ),
            "请先补充失败回滚方案。"
        )
    }

    func testFreeformTemplateCreatesTextOnlyQuestion() throws {
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "请提供数据库连接方式：",
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(question.header, "自由输入")
        XCTAssertTrue(question.options.isEmpty)
        XCTAssertTrue(question.allowsOther)
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["使用只读 PostgreSQL 连接。"]]
            ),
            "使用只读 PostgreSQL 连接。"
        )
    }

    func testExtractedRuleCanAllowMultipleSelections() throws {
        var rule = CompletionPromptRegexRule.defaultTemplates[1]
        rule.allowsMultiple = true
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: """
            请选择需要的能力：
            A. 审批
            B. 提问
            """,
            rules: [rule]
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertTrue(question.allowsMultiple)
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["A. 审批", "B. 提问"]]
            ),
            "选择 A：审批\n选择 B：提问"
        )
    }

    func testTrailingQuestionFallbackCreatesConfirmationAndYesActions() throws {
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "目前无法提取明确选项，你希望我继续处理吗？",
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(question.header, "结尾问句确认")
        XCTAssertEqual(question.options.map(\.title), ["确认", "是的"])
        XCTAssertTrue(question.allowsOther)
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["确认"]]
            ),
            "确认，请继续。"
        )
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["是的"]]
            ),
            "是的，请继续。"
        )
    }

    func testInlineOrTemplateExtractsTwoChoices() throws {
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "请选择 PostgreSQL 或 MySQL？",
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(question.header, "请选择 X 或 Y")
        XCTAssertEqual(question.options.map(\.title), [
            "A. PostgreSQL",
            "B. MySQL"
        ])
        XCTAssertEqual(
            CompletionPromptRegexParser.followUpMessage(
                for: match.intervention,
                answers: [question.id: ["B. MySQL"]]
            ),
            "选择 B：MySQL"
        )
    }

    func testDisabledInlineOrTemplateDoesNotMatchBeforeFallback() throws {
        var rules = CompletionPromptRegexRule.defaultTemplates
        let inlineIndex = try XCTUnwrap(rules.firstIndex {
            $0.id == "builtin-inline-or-options"
        })
        rules[inlineIndex].isEnabled = false

        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "请选择 PostgreSQL 或 MySQL？",
            rules: rules
        ))

        XCTAssertEqual(match.intervention.title, "结尾问句确认")
    }
}
