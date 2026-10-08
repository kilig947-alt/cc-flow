import Foundation

/// 宠物动画状态，完全对齐 Codex 9 状态规范，额外保留 `dragging` 用于拖拽手势。
enum MascotStatus: String, Codable, CaseIterable, Sendable {
    case idle = "idle"
    case runRight = "runRight"
    case runLeft = "runLeft"
    case waving = "waving"
    case jumping = "jumping"
    case failed = "failed"
    case waiting = "waiting"
    case running = "running"
    case review = "review"
    case dragging = "dragging"

    var displayName: String {
        switch self {
        case .idle: return AppLocalization.runtimeString("mascot.idle")
        case .runRight: return AppLocalization.runtimeString("mascot.working")
        case .runLeft: return AppLocalization.runtimeString("mascot.run_left")
        case .waving: return AppLocalization.runtimeString("mascot.wave")
        case .jumping: return AppLocalization.runtimeString("mascot.jump")
        case .failed: return AppLocalization.runtimeString("mascot.failed")
        case .waiting: return AppLocalization.runtimeString("mascot.waiting")
        case .running: return AppLocalization.runtimeString("mascot.working")
        case .review: return AppLocalization.runtimeString("mascot.reviewing")
        case .dragging: return AppLocalization.runtimeString("mascot.dragging")
        }
    }
}

// MARK: - Session → MascotStatus

extension MascotStatus {
    /// 单个会话的宠物状态（用于会话列表、hover 预览等位置）。
    /// 活跃任务统一映射到 `.runRight`（Codex 规范中 runRight 表示 running）。
    init(session: SessionState) {
        if session.needsApprovalResponse {
            self = .waiting
        } else if session.needsQuestionResponse {
            self = .review
        } else if session.phase.isActive {
            self = .runRight
        } else if !session.completedErrorToolIDs.isEmpty && session.phase == .ended {
            self = .failed
        } else if SessionCompletionStateEvaluator.isCompletedReadySession(session) {
            self = .waving
        } else {
            self = .idle
        }
    }
}

// MARK: - Closed Notch Aggregate Status

extension MascotStatus {
    /// flow Island关闭态右侧聚合宠物状态，按 Codex 状态规范显示。
    ///
    /// 优先级（从高到低）：
    /// 1. 最近有任务错误 → `.failed`
    /// 2. 最近有任务完成 → `.waving`
    /// 3. 有待审批权限 → `.waiting`
    /// 4. 有需要人工干预的输入 → `.review`
    /// 5. 有活跃/审批中任务 → `.runRight`（running 状态按 codex 规范用 runRight）
    /// 6. 无任务 → `.idle`（空闲中）
    static func closedNotchStatus(
        representativePhase: SessionPhase?,
        hasPendingPermission: Bool,
        hasHumanIntervention: Bool,
        hasCompletedReady: Bool,
        hasRecentTaskError: Bool,
        isAppActive: Bool
    ) -> MascotStatus {
        if hasRecentTaskError {
            return .failed
        }

        if hasCompletedReady {
            return .waving
        }

        if hasPendingPermission {
            return .waiting
        }

        if hasHumanIntervention {
            return .review
        }

        if let phase = representativePhase {
            if phase.isActive || phase.isWaitingForApproval {
                return .runRight
            }
            if phase == .waitingForInput {
                return .review
            }
        }

        return .idle
    }
}
