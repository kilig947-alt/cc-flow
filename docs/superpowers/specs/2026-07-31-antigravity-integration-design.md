# Antigravity 完整集成设计方案 (Conversation Records, Approval Hooks, Reply Recognition)

该设计方案旨在为 CC FLOW 引入对 Antigravity 平台的完整支持，包括会话记录解析、审批 Hook 以及回复识别。同时更新 `AGENTS.md` 以确保文档的准确性。

## 1. 目标与背景
CC FLOW 原本已具备 Claude Code 和 TRAE 的集成。用户目前希望能够完整适配 Antigravity，包括：
1. **会话记录展示**：能够解析 Antigravity 生成的 `transcript.jsonl` 日志，展示在 Island 窗口的历史列表中。
2. **审批 Hook (Approval Hooks)**：能够在 Antigravity 执行特权命令或读写文件时拦截审批请求，通过 CC FLOW Island UI 进行允许或拒绝。
3. **回复识别**：自动识别用户与模型的交互应答状态。

## 2. 详细设计方案

### 2.1 审批 Hook 适配 (`CCFlow/Models/ClientProfile.swift`)
在 [ClientProfile.swift](file:///Users/fha0020260421001/project/trae-flow/CCFlow/Models/ClientProfile.swift) 中，扩展 `antigravity-hooks` 的 `events` 列表，加入会话生命周期和权限审批的关键事件。

修改前的 events：
```swift
events: [
    HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PreInvocation", templates: [.plain]),
    HookInstallEventDescriptor(name: "PostInvocation", templates: [.plain]),
    HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
]
```

修改后的 events（与 Claude Code 保持对齐）：
```swift
events: [
    HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
    HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
    HookInstallEventDescriptor(name: "PermissionRequest", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PostToolUseFailure", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "PreCompact", templates: [.plain]),
    HookInstallEventDescriptor(name: "SubagentStart", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "SubagentStop", templates: [.matcher("*")]),
    HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
    HookInstallEventDescriptor(name: "SessionEnd", templates: [.plain]),
]
```

### 2.2 日志文件路径获取 (`CCFlow/Services/Hooks/HookSocketServer.swift`)
Antigravity 发送的日志文件路径参数是驼峰命名的 `transcriptPath`。修改 [HookSocketServer.swift](file:///Users/fha0020260421001/project/trae-flow/CCFlow/Services/Hooks/HookSocketServer.swift) 的 `sessionFilePath` 提取逻辑，添加对 `transcriptPath` 的支持：

```swift
let sessionFilePath = firstNonEmpty(
    metadata["session_file_path"],
    metadata["rollout_path"],
    metadata["transcript_path"],
    metadata["transcriptPath"]
)
```

### 2.3 日志格式解析 (`CCFlow/Services/Session/ConversationParser.swift`)
扩展 [ConversationParser.swift](file:///Users/fha0020260421001/project/trae-flow/CCFlow/Services/Session/ConversationParser.swift)，增加对 Antigravity 专属 JSONL 格式的处理。

#### 2.3.1 日志数据解析
在 `parseNewLines(filePath:state:)` 中，根据 `step_index` 识别 Antigravity 日志行：
* `USER_INPUT` -> 映射为角色为 `.user` 的 `ChatMessage`。
* `PLANNER_RESPONSE` -> 映射为角色为 `.assistant` 的 `ChatMessage`，包含 `.thinking`（思考过程）和 `.toolUse`（工具调用）内容块。
* 其他步骤（如 `RUN_COMMAND`、`VIEW_FILE` 等工具执行结果）-> 映射为工具调用返回值，完成状态绑定。

#### 2.3.2 列表预览抽取
修改 `parseContent(_:)`，在首尾扫描逻辑中支持从 `USER_INPUT` 和 `PLANNER_RESPONSE` 提取首条用户输入、最近一条消息以及时间戳，用以 Island 面板的历史会话列表展示。

### 2.4 回复识别
通过在 [ClientProfile.swift](file:///Users/fha0020260421001/project/trae-flow/CCFlow/Models/ClientProfile.swift) 中正确配置 `PermissionRequest` 的等待逻辑，以及在 [ConversationParser.swift](file:///Users/fha0020260421001/project/trae-flow/CCFlow/Services/Session/ConversationParser.swift) 中解析 `USER_INPUT` 和工具返回，系统原有的 `SessionStore` 会自动打通回复状态识别。

### 2.5 文档更新 (`AGENTS.md`)
修改 [AGENTS.md](file:///Users/fha0020260421001/project/trae-flow/AGENTS.md) 的相关说明，明确记录：
- Claude Code 的重新适配结果。
- Antigravity 原生支持会话记录、审批 Hook、回复识别功能。

## 3. 测试与验证计划
1. **编译验证**：使用 Xcode 编译运行项目，确保核心 App scheme 编译通过。
2. **逻辑测试**：运行 `Prototype` 中的 HookPayloadMapper 单元测试。
3. **功能验证**：模拟接收包含 `transcriptPath` 和 `PermissionRequest` 的 Antigravity 外部事件，验证 Island 界面弹出审批逻辑和记录完美展示。
