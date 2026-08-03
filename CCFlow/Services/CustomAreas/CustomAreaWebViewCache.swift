import AppKit
import Foundation
import WebKit

/// 展开态网站功能的 WKWebView 页面状态缓存。
///
/// 当 `Settings.keepWebURLAliveWhenCollapsed` 开启时，`CustomAreaWebView`（展开态）
/// 在 `makeNSView` 中将创建的 WKWebView 存入此缓存；SwiftUI 移除宿主视图时，
/// 缓存持有的强引用使 WKWebView 继续存活。下次展开时 `makeNSView` 从缓存取回
/// 同一实例并重新绑定 Coordinator。
///
/// Spec: 离屏窗口保活 —— 仅持有强引用不足以保持 WKWebView 的 JS 正常运行。
/// macOS WKWebView 在不在任何 NSWindow 中时会挂起/节流 JS 执行（timer、事件回调），
/// 导致 mineradio.art 播完一首歌后无法自动播放下一首（自动切歌逻辑依赖 JS）。
/// `dismantleNSView` 时将 WebView 移入离屏窗口，使其仍在窗口层级中，
/// web process 继续正常运行 JS。下次展开时 `makeNSView` 的 `removeFromSuperview()`
/// 会将其从离屏窗口移出。
///
/// 缓存键以功能实例 ID 为边界，避免相同 URL 的两个功能互相争用 WebView。
@MainActor
final class CustomAreaWebViewCache {
    static let shared = CustomAreaWebViewCache()

    struct Key: Hashable, Sendable {
        let rawValue: String

        static func expanded(featureID: String) -> Key {
            Key(rawValue: "expanded:\(featureID)")
        }

        /// 桌面小组件使用独立 WebView，避免与 Flow Island 展开态争用同一个 NSView。
        static func desktopWidget(featureID: String) -> Key {
            Key(rawValue: "desktop-widget:\(featureID)")
        }

        /// 兼容旧的仅按 URL 保活调用；展开态功能应优先使用 `expanded(featureID:)`。
        static func legacy(url: URL) -> Key {
            Key(rawValue: "legacy:\(url.absoluteString)")
        }
    }

    private struct Entry {
        let webView: WKWebView
        let entryURL: URL?
    }

    private var cache: [Key: Entry] = [:]
    private var appliedEntryReloadGenerations: [Key: UInt64] = [:]

    /// Spec: 离屏宿主窗口 —— 持有收起后的保活 WebView，使其仍在窗口层级中，
    /// 避免 macOS 挂起 WKWebView 的 JS 执行。
    private var offscreenHostWindow: NSWindow?

    private init() {}

    func webView(for key: Key) -> WKWebView? {
        cache[key]?.webView
    }

    func storeWebView(_ webView: WKWebView, for key: Key, entryURL: URL?) {
        if let replaced = cache.updateValue(Entry(webView: webView, entryURL: entryURL), forKey: key),
           replaced.webView !== webView {
            replaced.webView.removeFromSuperview()
        }
    }

    func evict(for key: Key) {
        if let entry = cache.removeValue(forKey: key) {
            entry.webView.removeFromSuperview()
        }
    }

    /// 兼容旧调用：查找 URL 对应的 legacy 缓存。
    func webView(for url: URL) -> WKWebView? {
        webView(for: .legacy(url: url))
    }

    func storeWebView(_ webView: WKWebView, for url: URL) {
        storeWebView(webView, for: .legacy(url: url), entryURL: url)
    }

    /// 兼容 URL 更新路径：清理所有入口 URL 匹配的缓存。
    func evict(for url: URL) {
        let keys = cache.compactMap { key, entry in
            entry.entryURL?.absoluteString == url.absoluteString ? key : nil
        }
        for key in keys {
            evict(for: key)
        }
    }

    /// 清空所有缓存 WKWebView。关闭保活设置或应用退出时调用。
    func clearAll() {
        for entry in cache.values {
            entry.webView.removeFromSuperview()
        }
        cache.removeAll()
        appliedEntryReloadGenerations.removeAll()
        offscreenHostWindow?.orderOut(nil)
        offscreenHostWindow = nil
    }

    /// 每个 feature key 的同一代重新进入请求只消费一次，不受 SwiftUI Coordinator 重建影响。
    func consumeEntryReload(for key: Key?, generation: UInt64?) -> Bool {
        guard let key, let generation else { return false }
        guard appliedEntryReloadGenerations[key] != generation else { return false }
        appliedEntryReloadGenerations[key] = generation
        return true
    }

    /// 停止隐藏页面的持续运行，但保留 WKWebView 实例以便下次恢复页面状态。
    func stopKeepingViewsRunning() {
        for entry in cache.values where entry.webView.window === offscreenHostWindow {
            entry.webView.removeFromSuperview()
        }
        offscreenHostWindow?.orderOut(nil)
        offscreenHostWindow = nil
    }

    /// Spec: 将 WebView 移入离屏宿主窗口，使其仍在窗口层级中。
    /// 由 `CustomAreaWebView.dismantleNSView` 在 flow Island收起时调用。
    /// 若 WebView 仍在某个窗口中（尚未被 SwiftUI 移除）则不做任何操作。
    func hostInOffscreenWindow(_ webView: WKWebView) {
        guard webView.window == nil else { return }
        let window = ensureOffscreenHostWindow()
        window.contentView?.addSubview(webView)
        // 给一个非零 frame，确保 WebView 不因 zero-size 被系统判定为不可见
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Spec: 懒创建离屏宿主窗口。窗口无边框、透明、不可交互、定位在屏幕外，
    /// 但保持 ordered-in 状态（非 orderOut），使 WKWebView 被 macOS 视为"在可见窗口中"，
    /// web process 的 JS 正常运行。
    private func ensureOffscreenHostWindow() -> NSWindow {
        if let window = offscreenHostWindow {
            return window
        }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        // stationary: 不出现在 Mission Control / Exposé 中
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // borderless 窗口默认 canBecomeKey/canBecomeMain 为 false，不会抢焦点
        // orderFront 使窗口 ordered-in（非 orderOut），WKWebView 被视为在窗口层级中
        window.orderFront(nil)
        offscreenHostWindow = window
        return window
    }
}
