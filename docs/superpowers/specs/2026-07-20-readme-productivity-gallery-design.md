# README 生产力功能示例图设计

## 目标

更新中文 `README.md` 与英文 `README.en.md`，加入用户提供的 6 张真实界面截图，让读者能直观看到 Flow Island 紧凑态及主要生产力功能。

## 图片资产

将临时剪贴板图片复制到 `docs/images/`，使用稳定、语义化的英文文件名：

- `flow-island-compact-usage.png`：紧凑态 Codex 剩余额度与任务数。
- `productivity-account-usage.png`：Claude Code / Codex 账号用量。
- `productivity-system-monitor.png`：CPU、内存、磁盘、负载和应用使用时间。
- `productivity-calendar.png`：月历与提醒事项。
- `productivity-github.png`：GitHub 账号、贡献记录和仓库。
- `productivity-file-watch.png`：目录授权、文件卡片和搜索入口。

图片保留原始 PNG 内容，不重新压缩或裁切。README 使用相对路径，确保 GitHub 和本地 Markdown 预览均可加载。

## 中文 README 编排

在“Flow Island 布局 / 紧凑态”中保留现有动画，并追加紧凑态用量截图及一句说明，突出左侧额度与右侧任务计数可同时显示。

在“生产力功能”附近新增“生产力功能预览”小节。使用 HTML table 双列布局：

1. 账号用量 / 系统监控
2. 日历 / GitHub
3. File Watch 单图占一格，另一格留空或跨列展示

每个单元格包含简短标题与截图。标题和 `alt` 文本使用中文。

## 英文 README 编排

与中文 README 使用相同图片、顺序和布局：

- 在 Compact State 部分追加 compact usage screenshot。
- 在 Productivity Features 附近新增 Productivity Feature Preview。
- 标题与替代文本使用自然英文，不逐字硬译。

## 可访问性与渲染

- 所有 `<img>` 提供明确 `alt` 文本。
- 双列图使用 `width="100%"`，由单元格约束宽度，适配 GitHub 页面宽度。
- 小尺寸紧凑态截图单独居中展示，避免被拉伸到失真。
- 不删除或替换现有设置面板、会话列表和会话交互截图。

## 验证

- 确认 6 个目标 PNG 存在且可由图片工具解码。
- 检查中英文 README 中的所有新增相对路径均指向真实文件。
- 检查 HTML table 标签闭合，Markdown 标题层级与现有目录结构一致。
- 使用 `git diff --check` 检查尾随空格与格式问题。

## 非目标

- 不重写 README 的安装、构建或 Hook 配置说明。
- 不修改应用代码。
- 不删除现有图片资产。
- 不重新设计项目品牌或 README 顶部主视觉。
