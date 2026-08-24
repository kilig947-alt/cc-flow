import SwiftUI

/// 灵动岛紧凑态左侧 Giflow 功能视图
struct GiflowCompactView: View {
    @ObservedObject private var store = GiflowStore.shared
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            if store.isRecording {
                // 录制中：呼吸红点 + 计时器
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.red.opacity(0.8), radius: isPulsing ? 3 : 1)
                    .scaleEffect(isPulsing ? 1.2 : 0.85)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                Text(formattedDuration)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            } else if store.isExporting {
                // 导出中：进度指示
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .scaleEffect(0.7)

                Text(store.exportProgress > 0 ? "\(Int(store.exportProgress * 100))%" : "导出中")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                // 待命状态：Giflow 图标
                Image(systemName: "record.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.9))

                Text("Giflow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if store.isRecording {
                GiflowOverlayController.shared.showRecordingControlMenu()
            } else {
                store.triggerSelectionCapture()
            }
        }
    }

    private var formattedDuration: String {
        let total = store.elapsedSeconds
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
