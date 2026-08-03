# Antigravity 完整集成设计方案与实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CC FLOW 引入对 Antigravity 平台的完整支持，包含会话记录历史、审批 Hook 以及回复状态识别。

**Architecture:**
1. 在 `ClientProfile.swift` 扩展 `antigravity-hooks` 的 `events`，添加生命周期与审批事件订阅。
2. 在 `HookSocketServer.swift` 支持读取驼峰命名 `transcriptPath` 的元数据。
3. 在 `ConversationParser.swift` 实现 Antigravity 特有 JSONL 格式的解析，提取消息、思考块和工具结果。
4. 更新说明文档 `AGENTS.md`。

**Tech Stack:** Swift, Combine, JSON Parsing, Unix Sockets

## Global Constraints
- 确保不会破坏 Claude Code 与 TRAE 变体的现有解析与通信流程。
- 解析器处理 Antigravity 产生的包含 `step_index` 字典行的 JSONL 文件。

---

### Task 1: 权限审批事件订阅配置

**Files:**
- Modify: `CCFlow/Models/ClientProfile.swift:528-534`

**Interfaces:**
- Consumes: `antigravity-hooks` 原始 Profile 定义
- Produces: 支持 `PermissionRequest` 的新 `antigravity-hooks` 实例

- [ ] **Step 1: 修改 ClientProfile.swift 中的 antigravity-hooks 订阅事件列表**

将 events 列表变更为包含生命周期与审批的完整列表：
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
            ],
```

- [ ] **Step 2: Commit**
```bash
git add CCFlow/Models/ClientProfile.swift
git commit -m "feat(profile): extend antigravity-hooks events list to support approvals and session lifecycle"
```

---

### Task 2: 支持获取 transcriptPath 路径

**Files:**
- Modify: `CCFlow/Services/Hooks/HookSocketServer.swift:682-686`

**Interfaces:**
- Consumes: 驼峰 `transcriptPath` 的 hook 元数据
- Produces: 正确返回的 `sessionFilePath`

- [ ] **Step 1: 修改 HookSocketServer.swift 以提取 transcriptPath**

将提取逻辑变更为：
```swift
        let sessionFilePath = firstNonEmpty(
            metadata["session_file_path"],
            metadata["rollout_path"],
            metadata["transcript_path"],
            metadata["transcriptPath"]
        )
```

- [ ] **Step 2: Commit**
```bash
git add CCFlow/Services/Hooks/HookSocketServer.swift
git commit -m "feat(hooks): support extracting sessionFilePath from transcriptPath in HookSocketServer"
```

---

### Task 3: 适配 Antigravity 日志流解析器

**Files:**
- Modify: `CCFlow/Services/Session/ConversationParser.swift`

**Interfaces:**
- Consumes: Antigravity JSONL `transcriptPath`
- Produces: 包含 `.user`、`.assistant` 角色及 `.toolUse` 等内容块的 `[ChatMessage]`

- [ ] **Step 1: 新增日期解析的 fallback 逻辑**

修改 `parseTimestamp` 方法：
```swift
    private static func parseTimestamp(_ value: String?) -> Date {
        guard let value else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? Date()
    }
```

- [ ] **Step 2: 实现 parseAntigravityLine 与 findLastUncompletedToolUse 解析方法**

在 `ConversationParser` 类体内注入：
```swift
    private func parseAntigravityLine(
        _ json: [String: Any],
        type: String,
        state: inout IncrementalParseState
    ) -> ChatMessage? {
        let stepIndex = json["step_index"] as? Int ?? 0
        let timestamp = Self.parseTimestamp(json["created_at"] as? String ?? json["timestamp"] as? String)
        
        if type == "USER_INPUT" {
            guard let content = json["content"] as? String,
                  let sanitized = SessionTextSanitizer.sanitizedDisplayText(content) else {
                return nil
            }
            return ChatMessage(
                id: "antigravity-user-\(stepIndex)",
                role: .user,
                timestamp: timestamp,
                content: [.text(sanitized)]
            )
        } else if type == "PLANNER_RESPONSE" {
            var blocks: [MessageBlock] = []
            
            if let thinking = json["thinking"] as? String,
               let sanitizedThinking = SessionTextSanitizer.sanitizedDisplayText(thinking) {
                blocks.append(.thinking(sanitizedThinking))
            }
            
            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                for (idx, toolCall) in toolCalls.enumerated() {
                    if let name = toolCall["name"] as? String {
                        let toolUseId = "antigravity-tool-\(stepIndex)-\(idx)"
                        state.seenToolIds.insert(toolUseId)
                        state.toolIdToName[toolUseId] = name
                        
                        var input: [String: String] = [:]
                        if let args = toolCall["args"] as? [String: Any] {
                            input = Self.stringDictionary(from: args)
                        }
                        blocks.append(.toolUse(ToolUseBlock(id: toolUseId, name: name, input: input)))
                    }
                }
            }
            
            guard !blocks.isEmpty else { return nil }
            return ChatMessage(
                id: "antigravity-assistant-\(stepIndex)",
                role: .assistant,
                timestamp: timestamp,
                content: blocks
            )
        } else {
            // Treat as tool result.
            let content = json["content"] as? String ?? json["output"] as? String
            let statusStr = json["status"] as? String ?? ""
            let isError = statusStr == "ERROR" || statusStr == "FAILURE"
            
            if let content = content {
                if let matchedToolUseId = findLastUncompletedToolUse(
                    in: state.messages,
                    completedToolIds: state.completedToolIds,
                    eventType: type
                ) {
                    state.completedToolIds.insert(matchedToolUseId)
                    state.toolResults[matchedToolUseId] = ToolResult(
                        content: content,
                        stdout: content,
                        stderr: nil,
                        isError: isError
                    )
                }
            }
            return nil
        }
    }

    private func findLastUncompletedToolUse(
        in messages: [ChatMessage],
        completedToolIds: Set<String>,
        eventType: String
    ) -> String? {
        let normalizedEvent = eventType.lowercased().replacingOccurrences(of: "_", with: "")
        
        for message in messages.reversed() {
            for block in message.content.reversed() {
                if case .toolUse(let toolUse) = block {
                    if !completedToolIds.contains(toolUse.id) {
                        let normalizedTool = toolUse.name.lowercased().replacingOccurrences(of: "_", with: "")
                        if normalizedTool == normalizedEvent || 
                           normalizedEvent.hasPrefix(normalizedTool) || 
                           normalizedTool.hasPrefix(normalizedEvent) {
                            return toolUse.id
                        }
                    }
                }
            }
        }
        
        for message in messages.reversed() {
            for block in message.content.reversed() {
                if case .toolUse(let toolUse) = block {
                    if !completedToolIds.contains(toolUse.id) {
                        return toolUse.id
                    }
                }
            }
        }
        
        return nil
    }
```

- [ ] **Step 3: 修改 parseNewLines 方法以路由 Antigravity 日志行**

修改 `parseNewLines(filePath:state:)`：
```swift
            } else if line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") {
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let message = parseMessageLine(json, seenToolIds: &state.seenToolIds, toolIdToName: &state.toolIdToName) {
                    newMessages.append(message)
                    state.messages.append(message)
                }
            } else if let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      json["step_index"] as? Int != nil,
                      let type = json["type"] as? String {
                if let message = parseAntigravityLine(json, type: type, state: &state) {
                    newMessages.append(message)
                    state.messages.append(message)
                }
            }
```

- [ ] **Step 4: 修改 parseContent 方法支持列表信息提取**

更新 `parseContent(_:)` 方法使其支持 `USER_INPUT` 和 `PLANNER_RESPONSE` 类型。

- [ ] **Step 5: Commit**
```bash
git add CCFlow/Services/Session/ConversationParser.swift
git commit -m "feat(parser): add support for parsing Antigravity JSONL transcript files"
```

---

### Task 4: 更新文档与测试验证

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: 修改 AGENTS.md 记录适配结论**

更新 `AGENTS.md` 中关于已移除非 TRAE 客户端识别层的条目，剔除/修改关于 Antigravity 的失效描述，记录对 Antigravity 和 Claude Code 适配现状。

- [ ] **Step 2: 运行编译与测试验证**
Run: `xcodebuild -workspace CCFlow.xcworkspace -scheme CCFlow -sdk macosx build` or equivalent script validation to verify build.

- [ ] **Step 3: Commit**
```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md to record Antigravity and Claude Code integration status"
```
