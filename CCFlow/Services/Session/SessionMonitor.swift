//
//  SessionMonitor.swift
//  CCFlow
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation
import os.log

extension Notification.Name {
    static let ccFlowSessionAutoApproved = Notification.Name("ccFlowSessionAutoApproved")
}

@MainActor
class SessionMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "ai.ccflow.app", category: "SessionMonitor")
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    nonisolated static var isRunningUnderXCTest: Bool {
        Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false
    private var allSessions: [SessionState] = []
    private var maintenanceTask: Task<Void, Never>?
    private var questionDraftCache = SessionQuestionDraftCache()
    private var telemetryPendingAttentionSessionIDs: Set<String> = []

    init(observeSharedState: Bool = true) {
        guard observeSharedState else { return }

        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        startEnergyAwareMaintenanceLoop()

        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisibleSessions()
            }
            .store(in: &cancellables)
    }

    deinit {
        maintenanceTask?.cancel()
    }

    // MARK: - Monitoring Lifecycle

    func questionDraft(sessionId: String, interventionId: String) -> SessionQuestionFormDraft? {
        questionDraftCache.draft(sessionId: sessionId, interventionId: interventionId)
    }

    func updateQuestionDraft(
        sessionId: String,
        interventionId: String,
        draft: SessionQuestionFormDraft
    ) {
        questionDraftCache.update(
            sessionId: sessionId,
            interventionId: interventionId,
            draft: draft
        )
    }

    func clearQuestionDraft(sessionId: String, interventionId: String) {
        questionDraftCache.clear(sessionId: sessionId, interventionId: interventionId)
    }

    func startMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true
        if maintenanceTask == nil {
            startEnergyAwareMaintenanceLoop()
        }

        // Periodic liveness sweep: removes sessions whose Claude process has
        // died without delivering SessionEnd, plus garbage-collects sessions
        // already in .ended phase. See SessionStore.startLivenessSweep for
        // details.
        Task {
            await SessionStore.shared.startLivenessSweep()
        }

        let handleHookEvent: @Sendable (HookEvent) -> Void = { [self] event in
            Task { @MainActor in
                await self.handleIncomingHookEvent(event)
            }
        }

        HookSocketServer.shared.start(
            onEvent: handleHookEvent,
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func handleIncomingHookEvent(_ event: HookEvent) async {
        let effectiveEvent = event
        let existingSession = await SessionStore.shared.session(for: effectiveEvent.sessionId)
        let auditMode = SessionAuditStore.shared.mode(for: effectiveEvent.sessionId)
        let shouldAutoApproveAllOperations =
            effectiveEvent.event == "PermissionRequest"
            && effectiveEvent.status == "waiting_for_approval"
            && (existingSession?.autoApprovePermissions == true || auditMode == .skipped)
        let similarOperationRule = effectiveEvent.similarOperationApprovalRule
        let shouldAutoApproveSimilarOperation: Bool
        if let similarOperationRule {
            shouldAutoApproveSimilarOperation = await SimilarOperationApprovalStore.shared.allows(
                similarOperationRule,
                forSessionID: effectiveEvent.sessionId
            )
        } else {
            shouldAutoApproveSimilarOperation = false
        }

        let isAutoApproving = shouldAutoApproveAllOperations || shouldAutoApproveSimilarOperation
        await SessionStore.shared.process(.hookReceived(effectiveEvent.withAutoApproving(isAutoApproving)))

        if auditMode == .skipped,
           let session = await SessionStore.shared.session(for: effectiveEvent.sessionId),
           let intervention = session.intervention,
           intervention.kind == .question,
           intervention.metadata["source"] == "completionRegex" {
            skipCompletionPrompt(sessionId: effectiveEvent.sessionId, automatically: true)
            return
        }

        if shouldAutoApproveAllOperations,
           let toolUseId = effectiveEvent.toolUseId,
           let session = await SessionStore.shared.session(for: effectiveEvent.sessionId) {
            appendApprovalAudit(
                session: session,
                resultLabel: auditMode == .skipped ? "已跳过 · 自动允许" : "自动允许",
                submittedMessage: auditMode == .skipped
                    ? "收到 \(effectiveEvent.event)；跳过人工审计并自动允许"
                    : "允许（本会话已启用自动审批）"
            )
            HookSocketServer.shared.respondToPermission(
                toolUseId: toolUseId,
                decision: "allow"
            )
            await SessionStore.shared.process(
                .permissionApproved(sessionId: effectiveEvent.sessionId, toolUseId: toolUseId)
            )
            NotificationCenter.default.post(
                name: .ccFlowSessionAutoApproved,
                object: nil,
                userInfo: [
                    "sessionId": effectiveEvent.sessionId,
                    "toolName": effectiveEvent.tool ?? "unknown",
                    "resultLabel": auditMode == .skipped ? "已跳过 · 自动允许" : "自动允许",
                    "iconName": auditMode == .skipped ? "forward.end.fill" : "checkmark.circle.fill",
                    "summary": auditMode == .skipped
                        ? "\(effectiveEvent.event) · \(effectiveEvent.tool ?? "工具") → 自动允许"
                        : MCPToolFormatter.formatAutoApprovalSummary(
                            toolName: effectiveEvent.tool ?? "unknown",
                            toolInput: effectiveEvent.toolInput
                        )
                ]
            )
            await TelemetryService.shared.recordAttentionResolved(
                session,
                resolution: "approve_all_operations_automatic"
            )
            return
        }

        // Some Codex hook payloads arrive with a transient status such as
        // `running_tool` even though the event itself is a PermissionRequest.
        // The pending hook and toolUseId are the authoritative response
        // target, so do not require the mapped status string here.
        if effectiveEvent.event == "PermissionRequest",
           shouldAutoApproveSimilarOperation,
           let toolUseId = effectiveEvent.toolUseId,
           let session = await SessionStore.shared.session(for: effectiveEvent.sessionId) {
            appendApprovalAudit(
                session: session,
                resultLabel: "允许相同操作 · 自动",
                submittedMessage: "允许（已匹配相同操作审批规则）"
            )
            HookSocketServer.shared.respondToPermission(
                toolUseId: toolUseId,
                decision: "allow"
            )
            await SessionStore.shared.process(
                .permissionApproved(sessionId: effectiveEvent.sessionId, toolUseId: toolUseId)
            )
            NotificationCenter.default.post(
                name: .ccFlowSessionAutoApproved,
                object: nil,
                userInfo: [
                    "sessionId": effectiveEvent.sessionId,
                    "toolName": effectiveEvent.tool ?? "unknown",
                    "resultLabel": "允许相同操作 · 自动",
                    "summary": MCPToolFormatter.formatAutoApprovalSummary(
                        toolName: effectiveEvent.tool ?? "unknown",
                        toolInput: effectiveEvent.toolInput
                    )
                ]
            )
            await TelemetryService.shared.recordAttentionResolved(
                session,
                resolution: "approve_same_operation_automatic"
            )
            return
        }

        if effectiveEvent.event == "PostToolUse",
           let toolUseId = effectiveEvent.toolUseId,
           let session = await SessionStore.shared.session(for: effectiveEvent.sessionId) {
            if session.activePermission?.toolUseId == toolUseId {
                appendApprovalAudit(
                    session: session,
                    resultLabel: "外部已允许",
                    submittedMessage: "审批已从终端或客户端提交"
                )
                HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                // Tool was approved externally (e.g. terminal) and completed.
                // Resolve the pending Island-side intervention.
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: effectiveEvent.sessionId, toolUseId: toolUseId)
                )
            } else if session.activePermission?.toolUseId != toolUseId {
                HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
            }
        }

        if effectiveEvent.event == "Stop", effectiveEvent.ingress != .remoteBridge {
            if effectiveEvent.provider == .codex,
               let toolUseId = effectiveEvent.toolUseId,
               let session = await SessionStore.shared.session(for: effectiveEvent.sessionId),
               session.intervention?.metadata["responseMode"] == "stop_hook_continuation",
               session.intervention?.metadata["originalToolUseId"] == toolUseId {
                // Keep the Codex Stop hook open until the user answers from the
                // notification. Its response becomes a continuation prompt in
                // the same Codex turn.
                return
            }

            if let toolUseId = effectiveEvent.toolUseId {
                HookSocketServer.shared.completePendingHookWithoutDecision(toolUseId: toolUseId)
            }
            HookSocketServer.shared.cancelPendingPermissions(sessionId: effectiveEvent.sessionId)
        }
    }

    func stopMonitoring() {
        hasStarted = false
        maintenanceTask?.cancel()
        maintenanceTask = nil
        Task {
            await SessionStore.shared.stopLivenessSweep()
        }
        HookSocketServer.shared.stop()
    }

    private func startEnergyAwareMaintenanceLoop() {
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                let policy = await MainActor.run {
                    EnergyGovernor.shared.policy
                }

                guard let interval = policy.sessionMaintenanceInterval else {
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }

                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    guard let self else { return }
                    self.refreshVisibleSessions()
                }

                await SessionStore.shared.process(
                    .pruneTimedOutExternalContinuations(now: Date())
                )
                await SessionStore.shared.pruneOrphanedSessions()
            }
        }
    }

    // MARK: - Permission Handling

    func setAuditMode(_ mode: SessionAuditMode, sessionId: String) {
        SessionAuditStore.shared.setMode(mode, for: sessionId)
        Task {
            await SessionStore.shared.process(
                .permissionAutoApprovalChanged(
                    sessionId: sessionId,
                    isEnabled: mode == .unrestricted || mode == .skipped
                )
            )

            if mode == .skipped,
               let session = await SessionStore.shared.session(for: sessionId),
               session.intervention?.metadata["source"] == "completionRegex" {
                await MainActor.run {
                    self.skipCompletionPrompt(sessionId: sessionId, automatically: true)
                }
            }
        }
    }

    func approveAllPermissionsForSession(sessionId: String) {
        SessionAuditStore.shared.setMode(.unrestricted, for: sessionId)
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  session.supportsUnrestrictedSessionApproval,
                  let permission = Self.approvalToolUseId(for: session) else {
                return
            }

            await SessionStore.shared.process(
                .permissionAutoApprovalChanged(sessionId: sessionId, isEnabled: true)
            )

            var pendingPermissionIDs =
                HookSocketServer.shared.pendingPermissionToolUseIDs(sessionId: sessionId)
            if !pendingPermissionIDs.contains(permission) {
                pendingPermissionIDs.insert(permission, at: 0)
            }

            for toolUseId in pendingPermissionIDs {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: toolUseId,
                    decision: "allow"
                )
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: sessionId, toolUseId: toolUseId)
                )
            }
            appendApprovalAudit(
                session: session,
                resultLabel: "允许本会话所有操作",
                submittedMessage: "允许本会话后续所有操作"
            )

            await TelemetryService.shared.recordAttentionResolved(
                session,
                resolution: "approve_all_operations_for_session"
            )
        }
    }

    func approvePermission(sessionId: String, forSession: Bool = false) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }
            let permission = Self.approvalToolUseId(for: session)
            await clearApprovalNotification(
                for: session,
                toolUseId: permission,
                decision: .approve
            )

            guard let permission else { return }

            if forSession {
                switch session.scopedApprovalAction {
                case .autoApprove:
                    appendApprovalAudit(
                        session: session,
                        resultLabel: "允许本会话所有操作",
                        submittedMessage: "允许本会话后续所有操作"
                    )
                    await SessionStore.shared.process(
                        .permissionAutoApprovalChanged(sessionId: sessionId, isEnabled: true)
                    )
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission,
                        decision: "approveForSession"
                    )
                    await TelemetryService.shared.recordAttentionResolved(
                        session,
                        resolution: "approve_for_session"
                    )
                    return

                case .allowSimilarOperation:
                    guard let activePermission = session.activePermission,
                          let rule = SimilarOperationApprovalRule.make(
                              provider: session.provider,
                              toolName: activePermission.toolName,
                              toolInput: activePermission.toolInput
                          ) else {
                        return
                    }
                    appendApprovalAudit(
                        session: session,
                        resultLabel: "允许相同操作 · 手动",
                        submittedMessage: "允许当前操作，并自动允许本会话中的相同操作"
                    )
                    await SimilarOperationApprovalStore.shared.allow(
                        rule,
                        forSessionID: sessionId
                    )
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission,
                        decision: "allow"
                    )
                    await TelemetryService.shared.recordAttentionResolved(
                        session,
                        resolution: "approve_same_operation"
                    )
                    return

                case .allowSession, .none:
                    break
                }
            }

            appendApprovalAudit(
                session: session,
                resultLabel: "已允许",
                submittedMessage: "允许"
            )
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission,
                decision: "allow"
            )

            await TelemetryService.shared.recordAttentionResolved(session, resolution: "approve")
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }
            let permission = Self.approvalToolUseId(for: session)
            await clearApprovalNotification(
                for: session,
                toolUseId: permission,
                decision: .deny(reason: reason)
            )

            guard let permission else { return }

            let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let auditSubmittedMessage: String
            if let trimmedReason, !trimmedReason.isEmpty {
                auditSubmittedMessage = "拒绝：\(trimmedReason)"
            } else {
                auditSubmittedMessage = "拒绝"
            }
            appendApprovalAudit(
                session: session,
                resultLabel: "已拒绝",
                submittedMessage: auditSubmittedMessage
            )
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission,
                decision: "deny",
                reason: reason
            )

            await TelemetryService.shared.recordAttentionResolved(session, resolution: "deny")
        }
    }

    private enum ApprovalDecision {
        case approve
        case deny(reason: String?)
    }

    private nonisolated static func approvalToolUseId(for session: SessionState) -> String? {
        if let toolUseId = session.activePermission?.toolUseId,
           !toolUseId.isEmpty {
            return toolUseId
        }

        guard let intervention = session.intervention,
              intervention.kind == .approval else {
            return nil
        }

        return [
            intervention.metadata["originalToolUseId"],
            intervention.metadata["toolUseId"],
            intervention.metadata["tool_use_id"],
            intervention.id
        ].compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private func clearApprovalNotification(
        for session: SessionState,
        toolUseId: String?,
        decision: ApprovalDecision
    ) async {
        guard session.needsApprovalResponse else { return }
        guard let toolUseId else { return }

        switch decision {
        case .approve:
            await SessionStore.shared.process(
                .permissionApproved(sessionId: session.sessionId, toolUseId: toolUseId)
            )
        case .deny(let reason):
            await SessionStore.shared.process(
                .permissionDenied(sessionId: session.sessionId, toolUseId: toolUseId, reason: reason)
            )
        }
    }

    func answerIntervention(
        sessionId: String,
        answers: [String: [String]],
        onSubmitted: (() -> Void)? = nil
    ) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }

            guard let intervention = session.intervention,
                  intervention.kind == .question else {
                return
            }

            if intervention.metadata["responseMode"] == "stop_hook_continuation" {
                guard let followUpMessage = CompletionPromptRegexParser.followUpMessage(
                    for: intervention,
                    answers: answers
                ),
                let toolUseId = intervention.metadata["originalToolUseId"],
                HookSocketServer.shared.hasPendingHookResponse(toolUseId: toolUseId) else {
                    return
                }

                HookSocketServer.shared.respondToIntervention(
                    toolUseId: toolUseId,
                    decision: "answer",
                    reason: followUpMessage
                )
                appendQuestionAudit(
                    session: session,
                    intervention: intervention,
                    answers: answers,
                    submittedMessage: followUpMessage
                )
                await SessionStore.shared.process(
                    .interventionResolved(
                        sessionId: sessionId,
                        nextPhase: .processing,
                        submittedAnswers: answers
                    )
                )
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
                onSubmitted?()
                return
            }

            if intervention.metadata["responseMode"] == "follow_up" {
                guard let followUpMessage = CompletionPromptRegexParser.followUpMessage(
                    for: intervention,
                    answers: answers
                ) else {
                    return
                }

                do {
                    _ = try await deliverFollowUpMessage(followUpMessage, to: session)
                } catch {
                    Self.logger.error(
                        "Unable to deliver completion-regex answer for \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }

                appendQuestionAudit(
                    session: session,
                    intervention: intervention,
                    answers: answers,
                    submittedMessage: followUpMessage
                )
                await SessionStore.shared.process(
                    .interventionResolved(
                        sessionId: sessionId,
                        nextPhase: .processing,
                        submittedAnswers: answers
                    )
                )
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
                onSubmitted?()
                return
            }

            guard let updatedInput = updatedHookToolInput(
                    for: intervention,
                    answers: answers,
                    clientInfo: session.clientInfo
                  ) else {
                return
            }

            // 使用正确的 toolUseId：优先使用 metadata 中保存的原始值
            let toolUseId = intervention.metadata["originalToolUseId"] ?? intervention.id
            HookSocketServer.shared.respondToIntervention(
                toolUseId: toolUseId,
                decision: "answer",
                updatedInput: updatedInput
            )
            appendQuestionAudit(
                session: session,
                intervention: intervention,
                answers: answers,
                submittedMessage: nil
            )

            await SessionStore.shared.process(
                .interventionResolved(
                    sessionId: sessionId,
                    nextPhase: .processing,
                    submittedAnswers: answers
                )
            )
            await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
            HookWalkthroughDemoRunner.shared.completeIfNeeded(
                sessionId: sessionId,
                intervention: intervention
            )
            onSubmitted?()
        }
    }

    /// Dismisses a completion-regex prompt without selecting or sending an
    /// answer. Codex Stop hooks receive an empty response so the originating
    /// process can finish instead of remaining blocked on the socket.
    func skipCompletionPrompt(
        sessionId: String,
        automatically: Bool = false,
        onSkipped: (() -> Void)? = nil
    ) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let intervention = session.intervention,
                  intervention.kind == .question,
                  intervention.metadata["source"] == "completionRegex" else {
                return
            }

            let isStopHookContinuation =
                intervention.metadata["responseMode"] == "stop_hook_continuation"
            if isStopHookContinuation,
               let toolUseId = intervention.metadata["originalToolUseId"] {
                HookSocketServer.shared.completePendingHookWithoutDecision(
                    toolUseId: toolUseId
                )
            }


            appendQuestionSkipAudit(
                session: session,
                intervention: intervention,
                automatically: automatically
            )

            if automatically {
                NotificationCenter.default.post(
                    name: .ccFlowSessionAutoApproved,
                    object: nil,
                    userInfo: [
                        "sessionId": sessionId,
                        "toolName": intervention.title,
                        "resultLabel": "已跳过 · 自动",
                        "iconName": "forward.end.fill",
                        "summary": "审计问题 · \(intervention.title) → 自动跳过"
                    ]
                )
            }

            await SessionStore.shared.process(
                .interventionResolved(
                    sessionId: sessionId,
                    nextPhase: isStopHookContinuation ? .ended : .idle,
                    submittedAnswers: nil
                )
            )
            await TelemetryService.shared.recordAttentionResolved(session, resolution: "skip")
            onSkipped?()
        }
    }

    private func appendQuestionSkipAudit(
        session: SessionState,
        intervention: SessionIntervention,
        automatically: Bool
    ) {
        let message = intervention.message.trimmingCharacters(in: .whitespacesAndNewlines)
        SessionAuditStore.shared.append(
            SessionAuditRecord(
                sessionId: session.sessionId,
                kind: .question,
                platformName: session.messageBadgeDisplayName,
                requestTitle: intervention.title,
                requestContent: message.isEmpty ? intervention.title : message,
                submittedMessage: automatically
                    ? "收到审计问题；本会话已开启完全跳过，动作：自动跳过"
                    : "跳过本次审计",
                resultLabel: automatically ? "已跳过 · 自动" : "已跳过"
            )
        )
    }

    private func appendApprovalAudit(
        session: SessionState,
        resultLabel: String,
        submittedMessage: String
    ) {
        let permission = session.activePermission
        let intervention = session.intervention
        var contentParts: [String] = []

        if let message = intervention?.message.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            contentParts.append(message)
        }
        if let toolInput = permission?.toolInput,
           let json = Self.prettyPrintedJSONObject(toolInput.mapValues(\.value)),
           !json.isEmpty {
            contentParts.append(json)
        } else if let formattedInput = permission?.formattedInput, !formattedInput.isEmpty {
            contentParts.append(formattedInput)
        }

        SessionAuditStore.shared.append(
            SessionAuditRecord(
                sessionId: session.sessionId,
                kind: .approval,
                platformName: session.messageBadgeDisplayName,
                requestTitle: permission?.toolName
                    ?? intervention?.title
                    ?? "工具审批",
                requestContent: contentParts.isEmpty
                    ? "未提供审批详情"
                    : contentParts.joined(separator: "\n\n"),
                submittedMessage: submittedMessage,
                resultLabel: resultLabel
            )
        )
    }

    private func appendQuestionAudit(
        session: SessionState,
        intervention: SessionIntervention,
        answers: [String: [String]],
        submittedMessage: String?
    ) {
        let questions = intervention.resolvedQuestions
        var contentParts: [String] = []
        let message = intervention.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            contentParts.append(message)
        }

        for question in questions {
            var lines = [question.prompt]
            lines.append(contentsOf: question.options.enumerated().map { index, option in
                "\(Self.optionSequenceLabel(for: index)). \(option.title)"
            })
            contentParts.append(lines.joined(separator: "\n"))
        }

        let answerMessage = Self.auditAnswerMessage(
            questions: questions,
            answers: answers,
            preferredMessage: submittedMessage
        )
        SessionAuditStore.shared.append(
            SessionAuditRecord(
                sessionId: session.sessionId,
                kind: .question,
                platformName: session.messageBadgeDisplayName,
                requestTitle: intervention.title,
                requestContent: contentParts.isEmpty
                    ? intervention.title
                    : contentParts.joined(separator: "\n\n"),
                submittedMessage: answerMessage,
                resultLabel: "已回答"
            )
        )
    }

    nonisolated static func auditAnswerMessage(
        questions: [SessionInterventionQuestion],
        answers: [String: [String]],
        preferredMessage: String?
    ) -> String {
        let containsSecretAnswer = questions.contains {
            $0.isSecret && !(answers[$0.id] ?? []).isEmpty
        }
        if !containsSecretAnswer,
           let preferredMessage = preferredMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredMessage.isEmpty {
            return preferredMessage
        }

        var lines: [String] = []
        var recordedQuestionIDs = Set<String>()
        for question in questions {
            guard let values = answers[question.id], !values.isEmpty else { continue }
            recordedQuestionIDs.insert(question.id)
            let answer = question.isSecret
                ? "[已隐藏敏感回答]"
                : values.joined(separator: "、")
            lines.append("\(question.prompt)：\(answer)")
        }

        for questionID in answers.keys.sorted()
        where !recordedQuestionIDs.contains(questionID) {
            let values = answers[questionID, default: []]
            if !values.isEmpty {
                lines.append(values.joined(separator: "、"))
            }
        }
        return lines.isEmpty ? "已提交回答" : lines.joined(separator: "\n")
    }

    private nonisolated static func prettyPrintedJSONObject(
        _ object: [String: Any]
    ) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func optionSequenceLabel(for index: Int) -> String {
        guard index >= 0 else { return "" }
        var remaining = index
        var label = ""
        repeat {
            if let scalar = UnicodeScalar(65 + remaining % 26) {
                label.insert(Character(scalar), at: label.startIndex)
            }
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return label
    }

    func sendSessionMessage(sessionId: String, text: String, expectedTurnId: String? = nil) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let session = await SessionStore.shared.session(for: sessionId) else {
            throw NSError(
                domain: "CCFlow.SessionMonitor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Session not found."]
            )
        }

        if session.supportsTmuxCLIMessaging {
            guard let target = await findTmuxTarget(for: session) else {
                throw NSError(
                    domain: "CCFlow.SessionMonitor",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find the terminal pane for this session."]
                )
            }

            guard await ToolApprovalHandler.shared.sendMessage(trimmed, to: target) else {
                throw NSError(
                    domain: "CCFlow.SessionMonitor",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to send the follow-up message to the terminal session."]
                )
            }

            return
        }

        guard session.isInTmux, let tty = session.tty else {
            throw NSError(
                domain: "CCFlow.SessionMonitor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Inline follow-up requires an active tmux-backed terminal session."]
            )
        }

        guard let target = await findTmuxTarget(tty: tty) else {
            throw NSError(
                domain: "CCFlow.SessionMonitor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Could not find the terminal pane for this session."]
            )
        }

        guard await ToolApprovalHandler.shared.sendMessage(trimmed, to: target) else {
            throw NSError(
                domain: "CCFlow.SessionMonitor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to send the follow-up message to the terminal session."]
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionArchived(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        guard sessions != allSessions else { return }
        allSessions = sessions
        refreshVisibleSessions()
    }

    private func refreshVisibleSessions() {
        let visibleSessions = filteredVisibleSessions(from: allSessions)
        let pendingSessions = visibleSessions.filter { $0.needsApprovalResponse || $0.needsQuestionResponse || $0.suppressInAppPromptControls }
        recordNewAttentionRequests(in: pendingSessions)
        if visibleSessions != instances {
            instances = visibleSessions
        }
        if pendingSessions != pendingInstances {
            pendingInstances = pendingSessions
        }
    }

    private func recordNewAttentionRequests(in pendingSessions: [SessionState]) {
        let currentIDs = Set(pendingSessions.map(\.sessionId))
        let newSessions = pendingSessions.filter { !telemetryPendingAttentionSessionIDs.contains($0.sessionId) }
        telemetryPendingAttentionSessionIDs = currentIDs

        for session in newSessions {
            Task {
                await TelemetryService.shared.recordAttentionRequested(session)
            }
        }
    }

    private func filteredVisibleSessions(from sessions: [SessionState]) -> [SessionState] {
        sessions.filter { !$0.shouldHideFromPrimaryUI }
    }

    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneTTY = parts[1].replacingOccurrences(of: "/dev/", with: "")
                if paneTTY == tty {
                    return TmuxTarget(from: target)
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func findTmuxTarget(for session: SessionState) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        let normalizedTTY = session.tty?
            .replacingOccurrences(of: "/dev/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPaneID = session.clientInfo.tmuxPaneIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: [
                    "list-panes",
                    "-a",
                    "-F",
                    "#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_tty}"
                ]
            )

            for line in output.components(separatedBy: "\n") {
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneID = parts[1]
                let paneTTY = parts.count >= 3
                    ? parts[2].replacingOccurrences(of: "/dev/", with: "")
                    : ""

                if normalizedPaneID?.isEmpty == false,
                   paneID == normalizedPaneID,
                   let target = TmuxTarget(from: target) {
                    return target
                }

                if normalizedTTY?.isEmpty == false,
                   paneTTY == normalizedTTY,
                   let target = TmuxTarget(from: target) {
                    return target
                }
            }
        } catch {
            // Fall back to the older pid/cwd matching path below.
        }

        if let pid = session.pid,
           let target = await TmuxController.shared.findTmuxTarget(forSessionPid: pid) {
            return target
        }

        return nil
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }

    private enum HookAnswerEncodingStrategy {
        case questionText
    }

    private nonisolated static func answerEncodingStrategy(for clientInfo: SessionClientInfo?) -> HookAnswerEncodingStrategy {
        .questionText
    }

    nonisolated static func updatedHookToolInput(
        rawJSON: String,
        answers: [String: [String]],
        clientInfo: SessionClientInfo? = nil
    ) -> [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var updated = payload
        let questions = payload["questions"] as? [[String: Any]] ?? []
        var encodedAnswers: [String: Any] = [:]

        let encodingStrategy = answerEncodingStrategy(for: clientInfo)

        for (index, question) in questions.enumerated() {
            let lookupKeys = [
                question["id"] as? String,
                question["question"] as? String,
                "\(index)"
            ].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            guard let values = lookupKeys.compactMap({ answers[$0] }).first, !values.isEmpty else { continue }
            let encodedValue: Any = values.count == 1 ? values[0] : values
            switch encodingStrategy {
            case .questionText:
                let outputKey = (question["question"] as? String)
                    ?? (question["prompt"] as? String)
                    ?? (question["id"] as? String)
                    ?? "\(index)"
                guard !outputKey.isEmpty else { continue }
                encodedAnswers[outputKey] = encodedValue
            }
        }

        updated["answers"] = encodedAnswers
        return updated
    }

    private func updatedHookToolInput(
        for intervention: SessionIntervention,
        answers: [String: [String]],
        clientInfo: SessionClientInfo
    ) -> [String: Any]? {
        guard let rawJSON = intervention.metadata["toolInputJSON"] else {
            return nil
        }

        var updatedInput = Self.updatedHookToolInput(rawJSON: rawJSON, answers: answers, clientInfo: clientInfo)
        if let transcriptCallId = intervention.metadata["transcriptCallId"], !transcriptCallId.isEmpty {
            updatedInput?["tool_call_id"] = transcriptCallId
            updatedInput?["call_id"] = transcriptCallId
        }
        return updatedInput
    }

    nonisolated static func defaultAnswers(for intervention: SessionIntervention) -> [String: [String]] {
        intervention.questions.reduce(into: [String: [String]]()) { partial, question in
            guard let firstOption = question.options.first?.title, !firstOption.isEmpty else { return }
            partial[question.id] = [firstOption]
        }
    }

    private nonisolated static func resolvePendingApprovalToolUseId(
        for sessionId: String,
        fallback: String?
    ) async -> String? {
        if let toolUseId = await SessionStore.shared.session(for: sessionId)?.activePermission?.toolUseId,
           !toolUseId.isEmpty {
            return toolUseId
        }

        guard let fallback, !fallback.isEmpty else { return nil }
        return fallback
    }

}
