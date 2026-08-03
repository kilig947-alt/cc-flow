import SwiftUI

/// 展开态左半区功能容器 —— 顶部左上角切换栏 + 主内容区
///
/// 布局：切换栏（功能图标按钮行）固定在顶部左上角，主内容区填充剩余空间。
/// `VStack(alignment: .leading)` 确保切换栏左对齐；主内容区用 `.frame(maxWidth: .infinity)`
/// 占满宽度。
struct LeftFeatureContainerView: View {
    @ObservedObject private var featureStore = LeftFeatureStore.shared
    @ObservedObject private var customAreaStore = CustomAreaStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 切换栏已移至展开态 header 行左侧，与右侧按钮同一水平线
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        if let active = featureStore.expandedActiveFeature {
            mainContent(for: active)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func mainContent(for feature: LeftFeature) -> some View {
        switch feature.kind {
        case .usage:
            UsageExpandedView()
        case .systemMonitor:
            SystemMonitorFeatureView(compact: false)
        case .calendar:
            CalendarFeatureView(compact: false)
        case .github:
            GitHubFeatureView(compact: false)
        case .fileCards:
            FileCardsFeatureView(compact: false)
        case .naturalSearch:
            FileCardsFeatureView(compact: false)
        case .downloadMonitor:
            DownloadMonitorFeatureView(compact: false)
        case .browserResources:
            BrowserResourcesFeatureView(compact: false)
        case .mailAssistant:
            MailAssistantFeatureView(compact: false)
        case .music:
            MusicExpandedView()
        case .shelf:
            ShelfExpandedView()
        case .customArea(let areaID):
            if let area = customAreaStore.areas.first(where: { $0.id == areaID }) {
                expandedWebView(source: .localArea(area), feature: feature)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // 目录已被删除但功能残留 —— 显示空状态
                customAreaMissingState
            }
        case .webURL(let urlString):
            // Spec: 远程 URL 功能 —— 构造 .remoteURL 源传入 CustomAreaWebView
            // keepsAlive 跟随 Settings.keepWebURLAliveWhenCollapsed，开启后收起 flow Island时 WebView 保活
            if let url = URL(string: urlString) {
                expandedWebView(source: .remoteURL(url), feature: feature)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // URL 无效 —— 显示空状态
                webURLInvalidState
            }
        case .newsnow(let baseURL):
            // Spec: 内置 NewsNow 功能 —— 构造 .remoteURL 源传入 CustomAreaWebView，与 .webURL 一致
            // keepsAlive 跟随 Settings.keepWebURLAliveWhenCollapsed
            if let url = URL(string: baseURL) {
                expandedWebView(source: .remoteURL(url), feature: feature)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                webURLInvalidState
            }
        case .mineradio(let pageURL):
            // Spec: mineradio-bridge-compat-layer —— 构造 .mineradio 源传入 CustomAreaWebView
            //（注入 Bridge user script + 注册 message handler + 共享 cookie store）
            // keepsAlive 跟随 Settings.keepWebURLAliveWhenCollapsed，开启后收起 flow Island时 WebView 保活
            if let url = URL(string: pageURL) {
                expandedWebView(source: .mineradio(url), feature: feature)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                webURLInvalidState
            }
        }
    }

    private func expandedWebView(
        source: CustomAreaWebView.ContentSource,
        feature: LeftFeature
    ) -> some View {
        let request = featureStore.expandedReentryRequest
        let generation = request?.featureID == feature.id ? request?.generation : nil
        let bridgeRebuildGeneration = feature.loadsMineradioBridge ? generation : nil
        return CustomAreaWebView(
            source: source,
            cacheKey: .expanded(featureID: feature.id),
            keepsAlive: settings.keepWebURLAliveWhenCollapsed,
            keepsCrossDomainLoginInWebView: feature.keepsCrossDomainLoginInWebView,
            loadsMineradioBridge: feature.loadsMineradioBridge,
            entryReloadGeneration: generation
        )
        .id("\(feature.id)-bridge-\(feature.loadsMineradioBridge)-reload-\(bridgeRebuildGeneration ?? 0)")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("未启用任何功能")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("在「设置 > 左侧功能」中启用功能")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customAreaMissingState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("自定义 HTML 目录不可用")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Spec: `.webURL` 功能 URL 无效时的空状态
    private var webURLInvalidState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("网站 URL 无效")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
