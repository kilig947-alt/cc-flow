import AppKit
import SwiftUI

struct BrowserResourcesFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = BrowserResourceService.shared
    @ObservedObject private var bridge = BrowserBridgeService.shared
    var body: some View {
        if compact {
            Label("已保存 \(service.resources.count) 个资源", systemImage: "safari").font(.system(size: 10, weight: .semibold))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("浏览器资源", systemImage: "safari").font(.headline)
                Text("兼容 Chrome、Edge 和 Safari。保存与分类只写入 CC FLOW，不修改浏览器书签。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bridge.status).font(.caption2).foregroundStyle(.secondary)
                if !bridge.isExtensionConnected { BrowserExtensionConnectionButtons() }
                HStack { TextField("https://…", text: $service.inputURL).textFieldStyle(.roundedBorder)
                    Button("保存资源") { service.saveCurrentInput() }.buttonStyle(.borderedProminent) }
                ScrollView { LazyVStack(spacing: 7) { ForEach(service.resources) { item in
                    HStack { Image(systemName: "link"); VStack(alignment: .leading) { Text(item.title).fontWeight(.semibold); Text(item.url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }; Spacer()
                        Button { NSWorkspace.shared.open(item.url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).frame(width: 44, height: 44)
                        Button { service.remove(item) } label: { Image(systemName: "trash") }.buttonStyle(.plain).frame(width: 44, height: 44)
                    }.padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                } } }
            }.padding(16)
        }
    }
}

struct BrowserExtensionConnectionButtons: View {
    @ObservedObject private var bridge = BrowserBridgeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择浏览器连接（点击后会复制配对令牌）")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(BrowserExtensionTarget.allCases) { target in
                    Button {
                        bridge.connect(to: target)
                    } label: {
                        Label(target.displayName, systemImage: target.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("复制配对令牌、收起 Flow Island 并打开 \(target.displayName)")
                }
            }
        }
    }
}

struct MailAssistantFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = MailAssistantService.shared
    private var codes: [MailSignal] { service.signals.filter { $0.verificationCode != nil } }
    var body: some View {
        Group {
            if compact {
                if let signal = codes.first, let code = signal.verificationCode {
                    HStack { Image(systemName: "envelope.badge"); Text(code).font(.system(size: 12, weight: .bold, design: .monospaced)); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain) }
                } else { Label("重要邮件 \(service.signals.count)", systemImage: "envelope.badge").font(.system(size: 10, weight: .semibold)) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("邮件助手", systemImage: "envelope.badge").font(.headline); Spacer(); if service.isLoading { ProgressView().controlSize(.small) }; Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }.frame(width: 44, height: 44) }
                    Text("只读取 Mail 最近邮件的发件人、主题与验证码；不会修改邮件状态或保存正文。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(service.status).font(.caption).foregroundStyle(.secondary)
                    ScrollView { LazyVStack(spacing: 7) { ForEach(service.signals) { signal in
                        HStack { VStack(alignment: .leading, spacing: 3) { Text(signal.subject).fontWeight(.semibold).lineLimit(1); Text(signal.sender).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); if let code = signal.verificationCode { Text(code).font(.system(.body, design: .monospaced).bold()).foregroundStyle(.green) } }
                            .padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    } } }
                }.padding(16)
            }
        }
    }
}
