import SwiftUI

/// A deliberately two-step control for enabling unrestricted, session-local
/// permission approval. The first click only arms the warning; the second
/// click performs the action.
struct UnrestrictedSessionApprovalButton: View {
    enum Density {
        case regular
        case compact

        var fontSize: CGFloat {
            switch self {
            case .regular: 12
            case .compact: 10
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: 12
            case .compact: 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular: 8
            case .compact: 4
            }
        }
    }

    let approvalIdentity: String
    var density: Density = .regular
    let onConfirmed: () -> Void

    @State private var isAwaitingConfirmation = false

    private var titleKey: String {
        isAwaitingConfirmation
            ? "请确认你的AI会遵循《阿西洛马 AI 原则》?"
            : "完全放任"
    }

    private var backgroundColor: Color {
        isAwaitingConfirmation
            ? Color(red: 0.38, green: 0.025, blue: 0.04)
            : Color.red.opacity(0.72)
    }

    var body: some View {
        Button {
            if isAwaitingConfirmation {
                isAwaitingConfirmation = false
                onConfirmed()
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isAwaitingConfirmation = true
                }
            }
        } label: {
            Text(AppLocalization.string(titleKey))
                .font(.system(size: density.fontSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .padding(.horizontal, density.horizontalPadding)
                .padding(.vertical, density.verticalPadding)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onChange(of: approvalIdentity) { _, _ in
            isAwaitingConfirmation = false
        }
    }
}
