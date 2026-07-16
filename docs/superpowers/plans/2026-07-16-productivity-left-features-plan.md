# CC FLOW 原生生产力左侧功能实施计划

> 依据：`docs/superpowers/specs/2026-07-16-productivity-left-features-design.md`
>
> 交付方式：按四个里程碑实施，每个里程碑单独建分支、测试、评审和合并。不得把全部功能堆积为一个不可审阅的提交。

## 统一接口与约束

- 在 `LeftFeatureKind` 增加 `.systemMonitor`、`.calendar`、`.github`、`.fileCards`、`.naturalSearch`、`.downloadMonitor`、`.browserResources`、`.mailAssistant`，并为每项增加稳定 ID、SF Symbol、显示名称、默认展开尺寸和紧凑/展开路由。
- 八项功能通过 `LeftFeatureStore` 幂等追加，默认 `isEnabled = false`；解码旧 `left-features.json` 必须兼容，禁用时必须停止对应服务。
- 共享服务使用依赖注入协议，生产实现由单例组合根持有，测试使用内存数据库、临时目录、假时钟、假权限和假客户端。
- 新持久化数据位于 `BridgeRuntimePaths.runtimeDirectoryURL/productivity/`；秘密只进入 Keychain。所有 schema 带显式版本与向前迁移，不在启动失败时静默删除数据。
- 所有后台服务暴露统一 `FeatureServiceState`：`disabled`、`permissionRequired(PermissionKind)`、`loading`、`ready(lastUpdated:)`、`degraded(message:)`、`failed(message:recovery:)`。
- 新 UI 使用原生 SwiftUI、现有材质与语义颜色；44pt 命中区域、键盘焦点、VoiceOver、降低动态效果、中英文和可恢复错误状态是完成条件。

## 里程碑 1：基础设施、系统监控与日历

### 1. 功能模型、迁移与生命周期

- 更新 `LeftFeature.swift`、`LeftFeatureStore.swift`、`NotchView.swift`、`LeftFeatureContainerView.swift` 和设置页的 kind 分发，加入八项内置功能的元数据与空壳路由。
- 新增 `featuresByEnsuringProductivityFeatures(_:)` 纯函数：保留已有功能顺序和用户状态，把缺失的新功能追加到末尾并保持默认关闭；重复执行不得改变结果。
- 为 `setFeatureEnabled`、`setExpandedActiveFeature` 和 AppDelegate 启停增加集中式 `ProductivityFeatureLifecycleCoordinator`，禁止在视图内直接管理全局后台服务。
- 测试旧 JSON 解码、稳定 ID、迁移幂等、排序不变、默认关闭、禁用停止和快捷键路由。

### 2. Keychain、权限与共享状态

- 新建 `ProductivitySecretsStore`，以 Security.framework 保存 OpenAI-compatible API key 与 GitHub PAT；接口仅提供 set/get/delete/availability，不发布秘密到 ObservableObject。
- 新建 `ProductivityPermissionCenter`，统一表达目录书签、EventKit、Mail Automation 与浏览器配对状态；权限必须由显式用户动作触发。
- 在设置页新增“生产力与 AI”区域：全局 Provider 默认值、CLI 检测、API base URL/模型、密钥写入/删除、权限总览和清除数据入口。每个功能编辑页可覆盖 AI Provider。
- 更新 `Info.plist` 的 Apple Events 描述，使其明确包含用户启用后的 Mail 读取；添加日历/提醒事项用途描述。保留现有 entitlement，不启用 App Sandbox。
- 测试 Keychain 错误映射、权限未请求状态、拒绝/撤销状态和设置持久化；测试中使用协议替身，不访问真实 Keychain 或系统权限面板。

### 3. AI Provider 层

- 定义 `AIProviderSelection`（local、codexCLI、claudeCLI、openAICompatible）和 `AITaskKind`（fileCard、organizationSuggestion、naturalQuery、browserClassification、mailImportance）。
- 定义 `AIProviderRequest`，只允许各 task 的最小结构化字段；定义版本化 `AIProviderResponse`，拒绝无法解码或包含未知执行动作的输出。
- 实现 Codex/Claude CLI 客户端：可注入可执行路径、受限环境、JSON stdin/stdout、超时、取消、最大输出和登录检测；不得拼接 shell 字符串。
- 实现 OpenAI-compatible 客户端：可配置 base URL 与模型，从 Keychain 临时读取密钥，设置请求超时并对 401、429、5xx 给出不同恢复信息。
- 实现 Local Rules Provider，并由 `AIProviderService` 按功能覆盖值→全局默认值解析；远程/CLI 失败时返回本地基础结果与 `degraded` 状态。
- 测试 Provider 解析优先级、最小字段编码、CLI 超时/取消/非法 JSON、API 认证/限流/服务错误和本地降级。

### 4. SQLite、事件与搜索基础层

- 使用系统 SQLite3 新建 `ProductivityDatabase` actor，启用 WAL、外键、事务和 schema migration；表包括 `file_cards`、`file_card_fts`、`browser_resources`、`mail_signals`、`suggestions`、`action_audit`、`browser_clients`。
- FTS 只同步 filename、path、summary、ocrText、tags；正文不得进入 schema。对删除、路径更新和授权撤销提供事务 API。
- 新建 `ProductivityEventStore` actor 和版本化事件枚举，负责写入事件并发布只读快照；文件、浏览器、邮件模块不得互相直接调用。
- 测试首次建库、逐版本迁移、事务回滚、FTS 字段边界、删除同步、损坏数据库恢复提示和索引重建。

### 5. 系统监控

- 新建 `SystemMonitorService`：用 `NSWorkspace` 前台应用通知和锁屏/唤醒/睡眠/空闲信号累计使用时间；按 bundle ID 聚合并每日切分。
- 增加网络字节、磁盘容量、内存压力和设备摘要采样器；保留短时环形缓冲，不永久保存逐秒网络样本。
- 更新频率由 `EnergyGovernor` 决定：展开时高频、紧凑态中频、后台低频、睡眠停止；禁用后释放通知与 timer。
- 实现 `SystemMonitorCompactView` 和展开态卡片：应用时长排序条形图、网络数值与短时趋势、磁盘/内存状态。趋势图提供暂停、数值摘要和 VoiceOver 文本。
- 测试跨午夜切分、锁屏/空闲排除、计数器回绕、采样降频、停止清理和告警优先级。

### 6. 日历

- 新建只读 `CalendarService`，通过 EventKit 获取授权范围内的月事件、当日日程和未完成提醒事项；缓存只保存展示所需字段。
- 实现 `CalendarCompactView` 和月历/当日双栏展开视图；事件颜色同时配合日历名称/图标，不以颜色作为唯一语义。
- 权限未决定时显示“授权访问”，拒绝时显示系统设置入口；不在启动或仅启用时自动弹权限框，首次点击授权按钮才请求。
- 测试授权状态、跨天/全天事件、时区与夏令时、重复事件、无事件空状态、提醒事项排序和只读约束。

### 7. 里程碑 1 验证

- 运行新增 focused tests、`xcodebuild ... -only-testing:CCFlowTests`、Debug build 和 `swift test --package-path Prototype`。
- 手动验证八项开关默认关闭、系统监控能耗状态、日历权限路径、Provider 切换、Keychain 删除和大字体/VoiceOver。
- 通过 `requesting-code-review` 评审后，只提交里程碑 1 文件并合并。

## 里程碑 2：文件卡片、确认执行与自然搜索

### 8. 目录授权与文件监控

- 新建 `WatchedFolderStore`，保存下载、桌面、截图目录和用户选定目录的安全作用域书签、启用状态、忽略规则和最后扫描游标。
- 新建 `FileIngestionService`：用目录级文件事件触发增量扫描；文件大小与修改时间在稳定窗口内不变后才入队。队列按 canonical URL 去重并限制并发。
- 目录授权失效或被移除时停止 scope、取消队列并从搜索结果隐藏对应记录；历史 File Card 的删除由用户单独选择。
- 测试书签恢复、重复目录、符号链接、隐藏文件、包目录、临时下载后缀、文件消失、持续写入和撤销权限。

### 9. OCR 与 File Card 流水线

- 定义 `FileCard`、`FileMetadata`、`OCRResult`、`OrganizationSuggestion` 和来源/处理状态；先写本地元数据，再异步追加 OCR 与 AI 增强。
- 图片与 PDF 可渲染页使用 Vision OCR；限制文件大小、页数和像素预算。失败或不支持时保留元数据卡片。
- 通过所选 AI Provider 生成摘要、标签和建议；发送内容只包含元数据和受预算限制的 OCR 文本。
- 实现 File Card 紧凑态（最新处理/待确认计数）和展开态列表/详情/筛选，长文本在渲染边界使用 `SessionTextSanitizer.boundedDisplayText` 或等价限制。
- 测试处理状态机、重复事件、OCR 预算、AI 降级、隐私字段裁剪、数据库 upsert 和搜索索引同步。

### 10. 建议确认、执行与撤销

- 新建 `FileActionExecutor` actor；输入只能是枚举化 rename/move/archive 建议，不接受任意 shell 命令。
- 确认页显示源路径、目标路径、名称变化、冲突和权限状态；执行时重新校验 file resource identifier、mtime 与目标是否存在。
- 目标冲突、源变化、scope 失效时终止并要求重新生成/确认，禁止覆盖。成功后在同一事务写入 File Card 新路径与 `action_audit`。
- 撤销只对源/目标身份仍匹配且不会覆盖文件的记录开放；失败时保留审计并解释恢复方式。
- 测试 rename/move/archive、跨卷移动、冲突、TOCTOU、部分失败、审计事务和撤销安全条件。

### 11. 自然搜索

- 新建 `NaturalSearchService`：Local Rules 解析关键词、路径、时间、类型和标签；AI Provider 可返回同一受限查询 AST，不允许生成 SQL。
- 查询编译器只把受限 AST 转为参数化 FTS/SQL，结果包含命中字段与片段；默认按相关度和新鲜度排序。
- 实现搜索紧凑态（最近查询/命中数）和展开态搜索框、建议、结果列表、匹配原因、Finder 定位与无结果恢复提示。
- 测试注入字符、中文分词退化、路径/标签过滤、权限撤销、无效 AI AST、本地回退和 Finder URL 验证。

### 12. 里程碑 2 验证

- 使用临时目录运行端到端测试：创建→稳定→OCR→File Card→建议→确认→移动→搜索→安全撤销。
- 验证所有危险动作都需要确认，禁用两个功能后 watcher、OCR、AI 与索引任务停止。
- 运行 focused tests、根单元测试、Debug build、Prototype tests 和 `./scripts/test.sh`，评审后独立合并。

## 里程碑 3：GitHub 与三浏览器扩展

### 13. GitHub 数据层与界面

- 新建 `GitHubCredentialResolver`，解析顺序为可用的 `gh auth`→Keychain PAT→未认证；提供显式“改用 PAT”和“重新检测 gh”。
- 新建 `GitHubService`，通过注入的进程/API 客户端读取用户、贡献日历、仓库摘要和近期事件；实现 ETag/时间缓存和限流状态。
- 实现 GitHub 紧凑态与展开态三块布局：资料、贡献热力图、仓库/活动。热力图提供图例、每周摘要、键盘焦点和 VoiceOver 数值替代。
- 测试认证回退、账号切换、分页、缓存、限流、私有数据最小化和贡献日期/时区。

### 14. 浏览器 bridge 协议

- 定义独立版本化 JSON 协议：`hello/pair`、`downloadStarted/Progress/Finished/Failed/Cancelled`、`pageSaved`、`resourceDetected`、`pageChanged`、`bookmarkSuggestionRequested` 和 ack/error。
- 扩展客户端只可发送来源浏览器、扩展版本、页面/下载最小元数据；本地 bridge 校验配对令牌、消息大小、URL scheme、事件速率和协议版本。
- 配对令牌存入 Keychain/扩展安全存储；设置页显示已配对客户端、最后连接、版本和撤销按钮。撤销后旧令牌立即失效。
- 使用与现有 hook socket 隔离的端点与处理器；不得复用 hook envelope 或开放文件读取/命令执行接口。
- 测试握手、令牌轮换、重放、超大消息、无效 URL、速率限制、版本不兼容、断连和多浏览器并发。

### 15. Chrome、Edge 与 Safari 扩展打包

- 在 `BrowserExtensions/Shared` 保存共用 TypeScript/JavaScript、manifest 模板和协议模型；Chrome/Edge 由同一 Manifest V3 构建产物生成品牌化目录。
- 新增 Safari Web Extension target 与最小容器配置，复用共享脚本；更新 Xcode scheme/build 脚本与签名说明，保证未配置开发者证书时主 App 单测仍可运行。
- 扩展权限只申请 downloads、activeTab、storage、必要的 bookmarks/notifications 能力；网页变化监控必须由用户显式 pin 页面后启用。
- 新增扩展构建校验脚本，检查 manifest、协议版本、禁止的 host 权限和产物一致性。

### 16. 下载监控与浏览器资源 UI

- `DownloadMonitorService` 从事件库派生活动与最近下载快照；限制进度刷新频率并在完成/失败时触发紧凑提示。
- `BrowserResourceService` 保存页面、资源、变化与分类建议；AI 只处理用户保存/pin 的条目，不后台上传任意浏览历史。
- 实现两项功能的紧凑/展开视图、浏览器连接空状态、Finder/浏览器跳转、分类确认和本地删除。
- 不写回浏览器书签；“接受分类”只更新 CC FLOW 本地资源卡片。
- 测试状态转换、重复下载 ID、浏览器重启、失败恢复、事件节流、隐私过滤和扩展撤销后的停止行为。

### 17. 里程碑 3 验证

- 分别在 Chrome、Edge、Safari 验证配对、下载五种状态、页面保存、网页变化、断连和撤销。
- 运行扩展协议/manifest 测试、GitHub 测试、根单元测试、主 App Debug build；在具备签名环境时构建 Safari extension。
- 完成安全审查与代码评审后独立合并。

## 里程碑 4：邮件助手、统一体验与发布收尾

### 18. Mail 本地适配器

- 定义 `MailClient` 协议和 Apple Events 生产实现，只读取用户配置邮箱/文件夹中的必要字段；默认查询最近窗口，按稳定邮件标识增量处理。
- `MailSignalClassifier` 先用本地规则提取验证码和重要规则命中；仅当用户为邮件助手选择 AI Provider 时发送最小主题/受限片段进行增强。
- 持久化只保存发件人、主题、时间、验证码、最小摘要和原邮件定位信息，不保存完整正文或附件。
- 提供邮箱/规则/保留期设置，默认验证码短期过期；权限拒绝、Mail 未运行和脚本超时各有恢复提示。
- 测试验证码格式、HTML/纯文本、重复邮件、过期清理、隐私裁剪、Automation 拒绝、超时和只读约束。

### 19. 邮件界面与通知路由

- 实现邮件紧凑态：优先显示未过期验证码，其次重要邮件计数；验证码提供显式复制按钮和自动过期视觉状态。
- 展开态按验证码/重要邮件分组，支持打开原邮件、标记 CC FLOW 内部已处理和删除本地信号；不得改变 Mail 状态。
- 将高优先级邮件、下载完成、文件建议接入现有紧凑 hint/通知队列，定义优先级、去重和自动消失时间，禁止覆盖人工审批会话。
- 测试复制、过期、跳转失败、队列优先级、去重和会话通知共存。

### 20. 设置、清理、能耗与可访问性统一

- 为八项功能补齐专属设置：权限、数据来源、采样/轮询、AI 覆盖、保留期、清除数据和诊断状态；复杂设置使用渐进展开。
- `ProductivityDataManager` 支持按功能清除和全部清除；清除前确认，清除结果可验证，不删除 Keychain 项除非用户同时选择。
- 审计所有 timer、notification observer、file descriptor、security scope 和 Task 生命周期；禁用、睡眠、退出和 URL/目录变更必须释放资源。
- 完成中英文文案、VoiceOver 顺序、键盘导航、44pt 命中区域、对比度、降低动态效果、大字体和错误恢复审核。
- 新增诊断摘要，只输出状态、计数和脱敏错误，不输出文件内容、邮件内容、令牌或 API key。

### 21. 全量验收与发布

- UI 测试覆盖八项功能的启用/禁用、拖拽排序、紧凑选择、展开路由、尺寸持久化、快捷键、权限空状态和数据清除。
- 运行 `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug build`、根单元测试、可运行的 UI 测试、`swift test --package-path Prototype` 和 `./scripts/test.sh`。
- 使用 Instruments/日志验证空闲、锁屏、睡眠和全部功能禁用时无高频轮询；记录合理基线并修复新增泄漏或持续唤醒。
- 更新 README、权限/隐私说明、浏览器扩展安装说明和发布说明；明确 Safari 构建/签名要求与 AI Provider 数据边界。
- 通过最终 `requesting-code-review`，按里程碑历史审阅 diff，确认无秘密、生成产物和用户无关改动后发布。

## 完成定义

- 八项功能均为独立内置左侧功能，能够启用、禁用、排序、紧凑/展开选择、调整尺寸和绑定快捷键。
- 未启用时不请求权限、不启动新后台工作；禁用后服务和资源完全停止。
- 文件、书签、邮件和日历的安全边界与设计规格一致，任何文件变更均经过用户确认且不覆盖冲突目标。
- AI 四种选项可逐项配置，失败时本地能力继续工作；秘密不出现在文件、日志或 UI 状态模型中。
- 三浏览器扩展协议通过安全测试，GitHub/Mail/EventKit/目录权限均有清晰恢复路径。
- 所有新增测试与仓库回归通过，能耗、无障碍、本地化和隐私验收完成。
