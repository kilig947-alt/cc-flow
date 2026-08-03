import SwiftUI

struct SessionAuditInnerView: View {
    let session: SessionState
    @ObservedObject var auditStore: SessionAuditStore
    @ObservedObject var viewModel: NotchViewModel

    @State private var isHeaderHovered = false

    private var records: [SessionAuditRecord] {
        auditStore.records(for: session.sessionId)
    }

    private let fadeColor = Color(red: 0.00, green: 0.00, blue: 0.00)

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if records.isEmpty {
                ContentUnavailableView(
                    "暂无审计记录",
                    systemImage: "checkmark.shield",
                    description: Text("此会话提交审批或问题回答后会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            auditCard(record)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.exitChat()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.6))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("审计记录")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.85))
                        Text(session.projectName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }

            Spacer()

            Text("\(records.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .padding(.trailing, 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [fadeColor.opacity(0.7), fadeColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)
            .offset(y: 12) // Push below header
            .allowsHitTesting(false)
        }
        .zIndex(1) // Render above records list
    }

    private func formattedResultLabel(for label: String) -> String {
        if label == "允许相同操作" {
            return "允许相同操作 · 手动"
        } else if label == "自动允许相同操作" {
            return "允许相同操作 · 自动"
        }
        return label
    }

    private func auditCard(_ record: SessionAuditRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: record.kind == .approval ? "checkmark.shield" : "questionmark.bubble")
                    .foregroundColor(record.kind == .approval ? TerminalColors.amber : TerminalColors.blue)

                Text(formattedResultLabel(for: record.resultLabel))
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                Text(record.platformName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(record.createdAt, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            auditSection(
                title: "审计内容",
                heading: record.requestTitle,
                content: record.requestContent
            )
            auditSection(
                title: "提交消息",
                heading: nil,
                content: record.submittedMessage
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func auditSection(
        title: String,
        heading: String?,
        content: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)

            if let heading, !heading.isEmpty {
                Text(heading)
                    .font(.system(size: 11, weight: .semibold))
                    .textSelection(.enabled)
            }

            Text(
                SessionTextSanitizer.boundedDisplayText(
                    content,
                    maxCharacters: 4_000,
                    truncationNotice: "内容过长，界面已截断；本地审计文件保留完整内容。"
                ) ?? ""
            )
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
