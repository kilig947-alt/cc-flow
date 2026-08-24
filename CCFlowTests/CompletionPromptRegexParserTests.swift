import XCTest
@testable import CC_FLOW

final class CompletionPromptRegexParserTests: XCTestCase {
    @MainActor
    func testOpenCodeIdleSynthesizesQuestionFromFinalAssistantMessage() async throws {
        let sessionID = "opencode-completion-regex-\(UUID().uuidString)"
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

        let idleEvent = HookEvent(
            sessionId: sessionID,
            cwd: "/tmp/project",
            event: "session.idle",
            status: "waitingForInput",
            provider: .opencode,
            clientInfo: SessionClientInfo(kind: .opencode, name: "OpenCode"),
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: "session.idle",
            message: """
            1. 修 bug / 稳定性 - 检查日志并修复现有问题。
            2. 重构前端状态管理 - 收敛状态入口。
            3. 后端性能优化 - 排查慢查询。

            选哪个？请问选哪个？
            """,
            messageRole: "assistant"
        )

        await store.process(.hookReceived(idleEvent))
        let snapshot = await store.session(for: sessionID)
        let session = try XCTUnwrap(snapshot)
        XCTAssertEqual(session.phase, .waitingForInput)
        XCTAssertEqual(session.intervention?.metadata["source"], "completionRegex")
        XCTAssertEqual(session.intervention?.metadata["responseMode"], "follow_up")
        XCTAssertEqual(
            session.intervention?.resolvedQuestions.first?.options.map(\.title),
            [
                "1. 修 bug / 稳定性 - 检查日志并修复现有问题。",
                "2. 重构前端状态管理 - 收敛状态入口。",
                "3. 后端性能优化 - 排查慢查询。"
            ]
        )
    }

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

    @MainActor
    func testSkippingCodexStopPromptClearsInterventionAndEndsSession() async throws {
        let sessionID = "completion-regex-skip-\(UUID().uuidString)"
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

        await store.process(.hookReceived(HookEvent(
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
            message: "请选择：\\nA. 继续\\nB. 取消"
        )))

        await store.process(.interventionResolved(
            sessionId: sessionID,
            nextPhase: .ended,
            submittedAnswers: nil
        ))

        let snapshot = await store.session(for: sessionID)
        let session = try XCTUnwrap(snapshot)
        XCTAssertEqual(session.phase, .ended)
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

    func testReviewTemplateRecognizesPleaseReviewWording() throws {
        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: "方案已经整理完成，请评审。",
            rules: CompletionPromptRegexRule.defaultTemplates
        ))

        XCTAssertEqual(match.intervention.title, "审阅与确认")
    }

    func testQuestionFollowedByRecommendationCreatesConfirmation() throws {
        let message = """
        选择 SQL 模板后，再点击更新查询条件时，应继续使用刚选中的模板，还是恢复默认数据库模板？

        我建议继续使用刚选中的模板；这样后续切换变量时，可以基于用户明确选择的模板重新解析。
        """

        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(match.intervention.title, "建议确认")
        XCTAssertEqual(question.options.map(\.title), ["确认，继续", "需要调整"])
    }

    func testFinalLineContainingExplicitConfirmationCreatesConfirmation() throws {
        let message = """
        ### 设计三：异常处理与兼容策略

        数据库加载失败时保留 SQL 草稿和已有结果。

        这一节是否确认？确认后我会整理完整中文设计规格并提交。
        """

        let match = try XCTUnwrap(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
        let question = try XCTUnwrap(match.intervention.resolvedQuestions.first)

        XCTAssertEqual(match.intervention.title, "明确确认")
        XCTAssertEqual(question.prompt, "这一节是否确认？确认后我会整理完整中文设计规格并提交。")
        XCTAssertEqual(question.options.map(\.title), ["确认，继续", "需要修改"])
    }

    func testListedOptionsAreExtractedAndRenderedAsExplicitReply() throws {
        let message = """
        请选择局部关系图需要包含的关系：

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
        XCTAssertEqual(match.intervention.message, message)
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

    func testNumberedAnalysisWithoutPleaseDoesNotCreateQuestion() {
        let message = """
        需要注意的实际问题有两个：

        1. pool_size=20 是全局通用配置，每个进程都有自己的池。
        2. 数据库故障时，消费者会定期重试，但不会累计成存活连接。

        结论：这里展示的是分析结果，并非向用户发起选择。
        """

        XCTAssertNil(CompletionPromptRegexParser.match(
            message: message,
            rules: CompletionPromptRegexRule.defaultTemplates
        ))
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
        var rule = try XCTUnwrap(CompletionPromptRegexRule.defaultTemplates.first {
            $0.id == "builtin-listed-options"
        })
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
