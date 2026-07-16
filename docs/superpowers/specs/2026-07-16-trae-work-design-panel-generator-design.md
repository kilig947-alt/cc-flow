# TRAE Work Design Panel Generator

## Summary

Add a panel-generation section below the left-feature list in Settings. It reuses the existing mascot-generation interaction: users can copy a fixed prompt, open Codex Design, Claude Code Design, or TRAE Work Design, and ask the AI to create a local HTML panel that uses CC FLOW's public JavaScript Bridge APIs.

Generated panels are written beneath `~/Library/Application Support/cc-flow/custom-areas/`. CC FLOW watches that root, validates newly generated panel directories, and registers valid panels automatically. Manual scanning and directory import remain available as recovery paths.

## Goals

- Make Codex Design, Claude Code Design, and TRAE Work Design guided entry points for creating custom left-side panels.
- Give the AI a complete, fixed prompt that documents output requirements and supported Bridge APIs.
- Automatically discover and register newly generated panels without letting the AI edit CC FLOW's central configuration.
- Preserve manual scan and directory selection as reliable fallbacks.
- Reuse existing Settings visual patterns, launcher behavior, custom-area storage, and WebView runtime.

## Non-goals

- Do not add a free-form requirement field to CC FLOW. Users describe their requirements in the TRAE Work Design conversation.
- Do not let generated content modify `custom-areas.json` directly.
- Do not expose Mineradio's internal message handlers as public panel APIs.
- Do not invent new Bridge APIs as part of this feature.
- Do not install or invoke a Design application automatically beyond opening the application selected by the user.

## Generated Panel Contract

Each generated panel lives in its own directory:

```text
~/Library/Application Support/cc-flow/custom-areas/<panel-id>/
├── index.html
└── cc-flow-panel.json       # optional
```

`index.html` is the default entry point. An optional `cc-flow-panel.json` provides metadata:

```json
{
  "id": "system-dashboard",
  "name": "系统仪表盘",
  "entryPoint": "index.html",
  "icon": "gauge.with.dots.needle.67percent",
  "allowsNetworkAccess": false
}
```

Rules:

- A directory without a manifest uses its directory name as the display name and `index.html` as its entry point.
- A manifest may override the display name, entry point, icon, and network permission.
- The entry point must resolve inside the panel directory and must exist as a regular file.
- A panel directory already represented by a `CustomArea` is not imported again.
- Invalid manifests and missing entry points produce visible scan issues and are not silently imported.
- The AI never writes the central `custom-areas.json` registry.

## Architecture

### Generated panel scanner

Introduce a focused `GeneratedPanelScanner` service responsible for:

- watching the managed custom-area root;
- debouncing filesystem events while the AI writes multiple files;
- enumerating immediate child directories;
- decoding the optional manifest;
- validating entry points and duplicate paths;
- returning import candidates and structured scan issues;
- registering valid candidates through `CustomAreaStore` on the main actor.

The scanner uses path identity as the primary duplicate guard because directory names and manifest IDs may be edited or reused. Registration continues through `CustomAreaStore.addArea(...)` so persistence and `LeftFeatureStore` synchronization remain centralized.

The scanner waits for a short quiet period after filesystem changes before scanning. A directory that is incomplete during one pass remains eligible for later passes, allowing an AI writer to create the directory before writing its entry point.

### Automatic discovery lifecycle

`AppDelegate` owns and starts automatic discovery after the custom-area and left-feature stores are initialized. This lifetime allows a generated panel to be registered even when Settings is not open. The scanner observes the managed root and schedules debounced scans until application termination.

Initial startup scanning must be conservative: it imports only valid directories not already present in `CustomAreaStore`. Existing registered built-in and user areas remain unchanged.

### Manual recovery paths

The feature-list title bar exposes two fallback actions:

- **Scan generated panels:** invokes the same managed-root scan used by automatic discovery and reports its result.
- **Choose directory to import:** opens a folder picker for an arbitrary local panel directory. The app validates the directory, saves a security-scoped bookmark, and imports it through `CustomAreaStore`.

Both paths share validation and import behavior with automatic discovery to avoid inconsistent rules.

## Settings UI

The feature-list card title bar places the panel recovery controls on its left side and retains “添加自定义功能” on its right side. The left control group contains “扫描生成功能”, “选择目录导入”, and the latest scan status. The controls remain compact and keep text or symbol-based success and error feedback.

The feature list sizes itself to its actual rows up to the current 330-point maximum. Short lists no longer leave a large empty region. Once the content exceeds the maximum, the list scrolls internally and retains drag-to-reorder behavior.

Add a `SettingsSectionCard` immediately below the feature-list card with the title “用 Design 生成功能”. Its layout follows the mascot-generation card:

1. An information row explains that the prompt should be copied and pasted into the selected Design conversation and that generated panels appear automatically.
2. Three equal-width primary buttons open “Codex Design”, “Claude Code Design”, or “TRAE Work Design”. Selecting a destination copies the fixed panel prompt before activating its desktop application. Codex and Claude use their desktop bundle identifiers with application-name fallback; TRAE Work uses `TraeSessionLauncher.activate(.traeWorkCN)`.
3. A prompt header contains “生成功能提示词” and a “复制提示词” action.
4. A selectable, monospaced, vertically scrollable prompt preview shows the full fixed template.

The existing Settings card style, system colors, SF Symbols, typography, and spacing remain the source of truth. The three external-app launch buttons are co-equal primary actions; copy, scan, and import are secondary actions. Controls have text labels, keyboard focus, and VoiceOver labels. Result states use text and symbols as well as color.

Copying the prompt changes the button label to “已复制” for two seconds. Scanning reports such results as “已导入 1 个面板”, “没有发现新面板”, or an actionable validation error. Automatic imports update the feature list immediately and surface a brief success status in the card.

## Fixed Prompt Requirements

The fixed prompt instructs TRAE Work Design to:

- ask the user what panel they want to build;
- choose a filesystem-safe panel ID;
- create a dedicated directory under the managed custom-area root;
- generate a directly loadable `index.html` using HTML, CSS, and JavaScript;
- optionally create `cc-flow-panel.json` using the documented schema;
- support light and dark appearances;
- avoid modifying CC FLOW source code or central registry files;
- use only documented public Bridge APIs;
- wrap Bridge calls in feature detection or `try/catch` so browser previews degrade safely;
- declare `allowsNetworkAccess: true` only when the requested panel needs external HTTP requests;
- tell the user to return to CC FLOW when generation finishes and mention manual scan/import recovery.

The prompt documents these public APIs.

### Compact hint

```js
window.webkit.messageHandlers.ccFlowHint.postMessage({
  text: "任务已完成",
  duration: 5000
});
```

Clear the current hint with:

```js
window.webkit.messageHandlers.ccFlowHint.postMessage({
  action: "clear"
});
```

### System metrics

Request a metrics snapshot with:

```js
window.webkit.messageHandlers.ccFlowMetrics.postMessage({});
```

Receive the response through:

```js
window.receiveMetrics = function (data) {
  // data.cpu
  // data.memoryUsed
  // data.memoryTotal
  // data.memoryPercent
  // data.loadOne
  // data.loadFive
  // data.loadFifteen
  // data.cores
};
```

The prompt explicitly excludes the Mineradio API, binary, and playback handlers.

## Data Flow

1. The user selects a Design destination; CC FLOW copies the fixed prompt and opens the chosen application.
2. The selected Design assistant asks for the desired panel and writes the generated files.
3. The root watcher receives filesystem changes and starts a debounced scan.
4. The scanner validates the directory, manifest, entry point, and duplicate path.
5. Valid candidates are registered through `CustomAreaStore`.
6. `CustomAreaStore` persists the area and asks `LeftFeatureStore` to add its feature.
7. Settings refreshes immediately, and the Flow Island can load the new panel.
8. Later source-file changes continue through the existing `CustomAreaWatcher` and WebView reload path.

## Error Handling

- **Missing entry point:** keep the directory untouched, do not import it, and report the missing file.
- **Malformed manifest:** report the manifest filename and decoding failure; allow the user or AI to fix it and trigger a later rescan.
- **Unsafe entry point:** reject absolute paths and traversal outside the panel directory.
- **Duplicate directory:** skip it without creating another `CustomArea` or `LeftFeature`.
- **Partially written output:** debounce and retry on later filesystem changes instead of permanently marking the directory invalid.
- **External-directory permission failure:** explain that the user must choose the directory again to grant access.
- **Watcher or scan failure:** leave existing features operational and keep both manual recovery actions available.
- **Launcher failure:** keep the prompt copyable and report which selected Design application could not be opened.

## Testing

Logic tests cover:

- importing a valid directory with a manifest;
- importing a valid directory without a manifest;
- mapping name, icon, entry point, and network permission correctly;
- rejecting missing, absolute, and directory-traversing entry points;
- reporting malformed manifests;
- skipping an already registered directory;
- repeated and debounced scans not creating duplicate features;
- incomplete directories becoming importable after their entry point appears;
- external directory import saving and using a security-scoped bookmark.

UI and integration coverage verifies:

- the feature list grows with its rows, caps at the existing maximum, and scrolls beyond it;
- scan, directory import, and scan status appear in the feature-list title bar;
- the generator card appears below the feature list with its updated title;
- the three launchers target Codex, Claude, and TRAE Work CN respectively and copy the prompt;
- copying the prompt updates and resets its feedback state;
- manual scan feedback distinguishes imports, empty results, and errors;
- directory selection imports a valid panel;
- automatic import updates the visible feature list.

Verification includes the relevant Xcode unit tests and a Debug app build. Manual QA checks light and dark appearance, keyboard focus, VoiceOver labels, long prompt scrolling and selection, launcher failure, and live generation while Settings is open and closed.
