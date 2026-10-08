import AppKit
import Foundation
import QuartzCore
import SwiftUI

extension Notification.Name {
    static let ccFlowHookWalkthroughDemoShouldCloseNotch = Notification.Name("ccFlowHookWalkthroughDemoShouldCloseNotch")
}

@MainActor
final class HookWalkthroughDemoRunner {
    static let shared = HookWalkthroughDemoRunner()

    static let metadataSource = "trae_flow_hook_walkthrough_demo"
    private static let completionDismissDelay: TimeInterval = 7
    private static let demoSessionCleanupDelayNanoseconds: UInt64 = 7_300_000_000

    private init() {}

    func start() {
        let sessionId = "cc-flow-demo-\(UUID().uuidString)"
        let cwd = FileManager.default.homeDirectoryForCurrentUser.path
        let toolUseId = Self.questionToolUseId(for: sessionId)
        let clientInfo = Self.demoClientInfo(sessionId: sessionId)

        HookWalkthroughDemoBackdropWindowController.shared.present()

        Task {
            await SessionStore.shared.process(.hookReceived(Self.notificationEvent(
                sessionId: sessionId,
                cwd: cwd,
                clientInfo: clientInfo
            )))

            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }

            await SessionStore.shared.process(.hookReceived(Self.questionEvent(
                sessionId: sessionId,
                cwd: cwd,
                clientInfo: clientInfo,
                toolUseId: toolUseId
            )))
        }
    }

    func completeIfNeeded(sessionId: String, intervention: SessionIntervention) {
        guard Self.isDemoIntervention(intervention) else { return }
        closeDockedNotchAfterAnswerIfNeeded()

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            let now = Date()
            let toolUseId = Self.questionToolUseId(for: sessionId)
            await SessionStore.shared.process(.toolCompleted(
                sessionId: sessionId,
                toolUseId: toolUseId,
                result: ToolCompletionResult(
                    status: .success,
                    result: AppLocalization.string("hooks.cc_flow_handled_this_demo_approval"),
                    structuredResult: nil
                )
            ))

            await SessionStore.shared.process(.historyLoaded(
                sessionId: sessionId,
                messages: [
                    ChatMessage(
                        id: "\(sessionId)-assistant-complete",
                        role: .assistant,
                        timestamp: now,
                        content: [.text(AppLocalization.string("hooks.hooks_approval_demo_complete_you_just_experienced_notification"))]
                    )
                ],
                completedTools: [toolUseId],
                toolResults: [:],
                structuredResults: [:],
                conversationInfo: ConversationInfo(
                    summary: AppLocalization.string("hooks.hooks_approval_demo_case"),
                    lastMessage: AppLocalization.string("hooks.hooks_approval_demo_complete_you_just_experienced_notification"),
                    lastMessageRole: "assistant",
                    lastToolName: nil,
                    firstUserMessage: AppLocalization.string("hooks.try_a_full_cc_flow_hooks_approval_notification"),
                    lastUserMessageDate: now
                )
            ))

            HookWalkthroughDemoBackdropWindowController.shared.dismiss(after: Self.completionDismissDelay)

            try? await Task.sleep(nanoseconds: Self.demoSessionCleanupDelayNanoseconds)
            guard !Task.isCancelled else { return }

            await SessionStore.shared.process(.sessionArchived(sessionId: sessionId))
        }
    }

    static func isDemoIntervention(_ intervention: SessionIntervention) -> Bool {
        intervention.metadata["source"] == metadataSource
    }

    private func closeDockedNotchAfterAnswerIfNeeded() {
        guard AppSettings.surfaceMode == .notch else { return }
        NotificationCenter.default.post(
            name: .ccFlowHookWalkthroughDemoShouldCloseNotch,
            object: nil
        )
    }

    private static func notificationEvent(
        sessionId: String,
        cwd: String,
        clientInfo: SessionClientInfo
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: "Notification",
            status: "processing",
            provider: .trae,
            clientInfo: clientInfo,
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: "hook_walkthrough",
            message: AppLocalization.string("hooks.starting_a_hooks_approval_walkthrough_notification_approval_submission")
        )
    }

    private static func questionEvent(
        sessionId: String,
        cwd: String,
        clientInfo: SessionClientInfo,
        toolUseId: String
    ) -> HookEvent {
        let toolInput: [String: AnyCodable] = [
            "questions": AnyCodable([
                [
                    "id": "demo_next_step",
                    "header": "1.",
                    "question": AppLocalization.string("hooks.approve_cc_flow_to_finish_this_walkthrough"),
                    "description": AppLocalization.string("hooks.choose_approve_and_continue_then_click_submit_cc"),
                    "options": [
                        [
                            "id": "approve",
                            "label": AppLocalization.string("hooks.approve_and_continue"),
                            "description": AppLocalization.string("hooks.simulates_approving_the_agent_to_continue")
                        ],
                        [
                            "id": "review",
                            "label": AppLocalization.string("hooks.review_then_continue"),
                            "description": AppLocalization.string("hooks.simulates_reviewing_risk_before_approving_continuation")
                        ]
                    ]
                ]
            ])
        ]

        return HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: "Notification",
            status: "waiting_for_input",
            provider: .trae,
            clientInfo: clientInfo,
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: toolInput,
            toolUseId: toolUseId,
            notificationType: "hook_walkthrough_question",
            message: AppLocalization.string("hooks.cc_flow_demo_is_waiting_for_a_demo"),
            bridgeIntervention: SessionIntervention(
                id: toolUseId,
                kind: .question,
                title: AppLocalization.string("hooks.cc_flow_demo_approval"),
                message: AppLocalization.string("hooks.choose_approve_and_continue_then_click_submit_after"),
                options: [],
                questions: [
                    SessionInterventionQuestion(
                        id: "demo_next_step",
                        header: "1.",
                        prompt: AppLocalization.string("hooks.approve_cc_flow_to_finish_this_walkthrough"),
                        detail: AppLocalization.string("hooks.choose_approve_and_continue_then_click_submit_cc"),
                        options: [
                            SessionInterventionOption(
                                id: "approve",
                                title: AppLocalization.string("hooks.approve_and_continue"),
                                detail: AppLocalization.string("hooks.simulates_approving_the_agent_to_continue")
                            ),
                            SessionInterventionOption(
                                id: "review",
                                title: AppLocalization.string("hooks.review_then_continue"),
                                detail: AppLocalization.string("hooks.simulates_reviewing_risk_before_approving_continuation")
                            )
                        ],
                        allowsMultiple: false,
                        allowsOther: false,
                        isSecret: false
                    )
                ],
                supportsSessionScope: false,
                metadata: [
                    "source": metadataSource,
                    "originalToolUseId": toolUseId,
                    "toolUseId": toolUseId,
                    "toolName": "AskUserQuestion",
                    "toolInputJSON": Self.toolInputJSONString(from: toolInput) ?? ""
                ]
            )
        )
    }

    private static func demoClientInfo(sessionId: String) -> SessionClientInfo {
        SessionClientInfo(
            kind: .custom,
            profileID: "cc-flow-demo",
            name: "CC FLOW Demo",
            launchURL: "ccflow://demo/\(sessionId)",
            origin: "demo"
        )
    }

    private static func questionToolUseId(for sessionId: String) -> String {
        "\(sessionId)-ask-user-question"
    }

    private static func toolInputJSONString(from input: [String: AnyCodable]) -> String? {
        let object = input.mapValues(\.value)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
private final class HookWalkthroughDemoBackdropWindowController: NSWindowController {
    static let shared = HookWalkthroughDemoBackdropWindowController()

    private let hostingController = NSHostingController(
        rootView: AppLocalizedRootView {
            HookWalkthroughDemoBackdropView()
        }
    )
    private var dismissWorkItem: DispatchWorkItem?

    private init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        dismissWorkItem?.cancel()
        guard let window else { return }
        let wasVisible = window.isVisible
        let targetScreen = ScreenSelector.shared.selectedScreen ?? NSScreen.main
        if let frame = targetScreen?.frame {
            window.setFrame(frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible {
            window.alphaValue = 0
        }
        showWindow(nil)
        window.orderFrontRegardless()
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
        }
        dismiss(after: 75)
    }

    func dismiss(after delay: TimeInterval = 0) {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutAndOrderOut()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func fadeOutAndOrderOut() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 0
        }
    }
}

private struct HookWalkthroughDemoBackdropView: View {
    var body: some View {
        ZStack {
            GlassEffectBackdrop(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(0.24)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color(red: 0.04, green: 0.07, blue: 0.09).opacity(0.30),
                    Color.black.opacity(0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                Text(appLocalized: "hooks.cc_flow_demo_mode")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))

                Text(appLocalized: "hooks.choose_an_option_in_the_island_approval_card")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 58)
        }
    }
}

private struct GlassEffectBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = true
    }
}
