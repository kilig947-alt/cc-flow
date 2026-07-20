# 左侧功能页面状态缓存设计

## 背景

Flow Island 展开态顶部的 `LeftFeatureSwitcherBar` 用于切换左侧功能。当前
`LeftFeatureContainerView` 只渲染激活功能；功能切换或面板收起时，SwiftUI 会移除当前
内容视图。远程 URL 和 Mineradio 虽已有可选的 `WKWebView` 保活缓存，但它依赖
`keepWebURLAliveWhenCollapsed`，以入口 URL 为缓存键，并且不覆盖本地自定义 HTML。
因此网站型功能返回时可能从入口重新加载，丢失滚动位置、站内路由、表单和运行中的
JavaScript 状态。

## 目标交互

- 悬浮展开、面板收起、切换到其他功能再返回时，恢复该功能上一次的页面状态。
- 页面状态包括当前 URL、浏览历史、滚动位置、表单、播放器和 JavaScript 运行状态。
- 只有再次点击当前已经高亮的功能图标时，才“重新进入”该功能的配置入口页。
- 重新进入不清除 Cookie、Local Storage、IndexedDB 等网站数据，登录态继续保留。
- 首次点击未激活图标只执行功能切换，不刷新或重置目标页面。

## 范围

本次覆盖使用 `CustomAreaWebView` 的展开态功能：

- `.customArea`
- `.webURL`
- `.newsnow`
- `.mineradio`

原生 SwiftUI 功能（用量、系统监控、日历、GitHub、文件卡片等）保持现有生命周期。
紧凑态 WebView 不参与展开态缓存，避免同一 `WKWebView` 同时被两个视图层级争用。

## 方案

### 1. 以功能实例为缓存边界

扩展 `CustomAreaWebViewCache`，使用稳定的展开态缓存键，而不是仅使用入口 URL。缓存键
由展示上下文和 `feature.id` 组成，例如 `expanded:<feature-id>`。这样两个配置为相同 URL
的功能仍拥有独立页面状态，紧凑态也不会取走展开态实例。

`LeftFeatureContainerView` 为四类网站型功能传入展开态缓存键，并始终启用页面状态缓存。
现有“收起后保持运行”设置继续控制离屏页面是否持续执行音频、计时器和网络活动，但不再
决定页面实例能否恢复：

- 开启：缓存 WebView 移入离屏宿主窗口，页面继续运行。
- 关闭：缓存 WebView 仍被保留以恢复可见状态，但进入非活动态时暂停或停止非必要运行；
  再次显示时复用同一实例，不主动加载入口 URL。

如果 WebKit 在非活动状态下自行冻结页面，这是允许的；恢复后仍应保持同一文档和导航状态。

### 2. 区分“选择”与“重新进入”

`LeftFeatureSwitcherBar` 在点击按钮前判断该功能是否已经激活：

- 未激活：调用 `setExpandedActiveFeature`，随后显示目标功能，不发送重置请求。
- 已激活：不重复写选择状态，发送针对该 `feature.id` 的重新进入请求。

重新进入请求使用显式、带 feature ID 的命令，不使用布尔状态，确保连续点击都能产生独立事件。
容器接收命令后只重置对应的网站型功能。原生功能的重复点击暂不新增行为。

### 3. 重新进入语义

对命中的缓存 WebView 调用入口加载操作：

- `.customArea`：重新加载当前自定义区域的入口文件。
- `.webURL` / `.newsnow`：加载功能配置的入口 URL。
- `.mineradio`：加载配置的 Mineradio 页面 URL，并继续使用共享 Cookie 与 Bridge 配置。

该操作会重置当前站内导航、滚动位置和页面内临时状态，但不会删除持久化网站数据。
若缓存尚未创建，则下一次构建正常加载入口，不额外加载两次。

### 4. 缓存失效与资源管理

以下情况清理对应 feature ID 的缓存：

- 功能被删除或禁用。
- 网站 URL、Mineradio URL 或自定义区域入口发生变化。
- 应用级缓存清理被触发。

清理时解除 message handler、navigation/UI delegate、Mineradio 协调器引用和离屏窗口宿主，
避免旧 WebView 继续运行或泄漏。现有按 URL 清理的调用迁移到 feature ID 清理；必要时保留
URL 批量清理作为兼容辅助。

## 数据流

1. 用户悬浮展开 Flow Island。
2. `LeftFeatureContainerView` 按 `expanded:<feature-id>` 获取缓存的 WebView。
3. 命中缓存时重新绑定当前 SwiftUI Coordinator，但不调用入口加载。
4. 用户切换图标，旧 WebView 进入缓存，目标 WebView从缓存恢复。
5. 用户再次点击当前高亮图标，Switcher 发出重新进入命令。
6. 缓存定位该 feature ID 的 WebView，并加载配置入口。

## 错误处理

- 无效入口 URL 继续显示现有错误空状态，不创建缓存。
- 重新进入时目标缓存不存在，记录待重置代次；视图创建后只执行一次入口加载。
- WebView 加载失败继续交给现有导航错误处理，不回退为销毁并重建。
- 缓存键冲突通过展示上下文与 feature ID 组合规避。

## 验证

增加逻辑级测试覆盖：

- 首次选择未激活图标只切换，不产生重新进入命令。
- 再次点击激活图标产生一次带正确 feature ID 的命令。
- 不同 feature ID 即使入口 URL 相同也映射到不同缓存项。
- 功能禁用、删除或 URL 修改时只清理目标缓存。
- 重新进入加载入口，但不清除网站数据存储。

手工验证 NewsNow 页面：滚动并进入二级内容后，收起/展开和切换返回均保持原位置；再次点击
高亮图标后回到 NewsNow 入口。另验证 Mineradio 播放、登录态和自定义 HTML 页面恢复。

## 非目标

- 不为所有原生 SwiftUI 功能建立常驻视图栈。
- 不跨应用重启恢复网页内存状态。
- 不改变功能排序、拖拽、固定面板或任务列表按钮行为。
- 不改变网站 Cookie 与本地存储的持久化策略。
