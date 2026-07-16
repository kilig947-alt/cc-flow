<h1 align="center">
  CC FLOW
</h1>
<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b>
</p>
<p align="center">
  <b>A macOS menu bar hub for Claude Code, Codex, and TRAE sessions</b><br>
  <a href="#installation">Installation</a> •
  <a href="#features">Features</a> •
  <a href="#productivity-features">Productivity</a> •
  <a href="#building-from-source">Build</a> •
  <a href="docs/privacy-policy.md">Privacy</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.1-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.1">
  <img src="https://img.shields.io/badge/Clients-Claude%20%7C%20Codex%20%7C%20TRAE-111827?style=flat-square" alt="Claude Code, Codex, and TRAE support">
  <img src="https://img.shields.io/badge/License-Apache%202.0-4F46E5?style=flat-square" alt="Apache 2.0 license">
</p>

<p align="center">
  <sub>Monitor active AI coding sessions, respond to approvals, and jump back to the matching terminal, tmux pane, or IDE from a native macOS Flow Island.</sub>
</p>

<p align="center">
  <img src="docs/images/settings-panel.png" alt="CC FLOW settings" width="760">
</p>

## What is CC FLOW?

CC FLOW is a native macOS menu bar app. When a Claude Code, Codex, or TRAE session needs attention, it expands into a compact Dynamic Island-style panel. It receives approval, question, tool, compaction, subagent, and lifecycle events through each client's supported hook interface.

Beyond session monitoring, CC FLOW provides independently enabled and ordered productivity features, media controls, a temporary file shelf, local HTML panels, and remote web panels.

Claude Code and Codex are enabled by default. TRAE, TRAE CN, TRAE WORK, and TRAE WORK CN appear when the corresponding app or an existing hook profile is detected. CC FLOW uses its own app identity and runtime directories and does not import legacy TRAE FLOW settings or assets.

## Features

- **Claude Code, Codex, and TRAE support** — Claude Code and Codex are first-class defaults, with compatibility for four TRAE variants.
- **Split Flow Island layout** — the left side displays a feature or session detail; the right side aggregates attention counts and jump-back actions.
- **Independent left features** — enable, disable, select, and reorder built-in or custom features, with per-feature expanded sizes.
- **Productivity workspace** — File Watch, Download Monitor, Browser Resources, Mail Assistant, Calendar, GitHub, and AI HOT.
- **Proactive notifications** — new downloads, completed downloads, browser resources, local mail signals, and due reminders can open their matching feature.
- **Music controls** — artwork, metadata, progress, and playback controls for system media players.
- **File shelf** — temporarily hold files and share them through AirDrop.
- **Custom HTML and websites** — embed local panels or remote pages with configurable icons, names, network access, and compact hints.
- **Official hook profiles** — manage Claude Code, Codex, and detected TRAE hook configuration without deleting user-owned hooks.
- **Jump back to context** — return to the captured terminal, tmux pane, IDE, or client deep link.
- **In-island actions** — approve tools, reject requests, and answer supported questions without hunting for the original window.
- **Animated pets** — spritesheet themes, desktop detachment, scroll-to-resize, and Codex pet compatibility.

## Supported clients

| Client | Shown by default | Hook configuration | In-island response |
| --- | --- | --- | --- |
| Claude Code | Yes | `~/.claude/settings.json` | Approvals and AskUserQuestion |
| Codex | Yes | `~/.codex/hooks.json` | PermissionRequest approval; general questions jump back to the terminal |
| TRAE family | When detected | See below | Approvals and questions supported by official hooks |

TRAE compatibility variants:

| Variant | Bundle ID | URL scheme | Official hook | Profile ID |
| --- | --- | --- | --- | --- |
| TRAE | `com.trae.app` | `trae://` | `~/.trae/hooks.json` | `trae` |
| TRAE CN | `cn.trae.app` | `trae-cn://` | `~/.trae-cn/hooks.json` | `trae-cn` |
| TRAE WORK | `com.trae.solo.app` | `solo://` | Not currently available | `trae-work` |
| TRAE WORK CN | `cn.trae.solo.app` | `solo-cn://` | Not currently available | `trae-work-cn` |

TRAE and TRAE CN expose official hooks. Current TRAE WORK clients do not, so their hook state is shown as unavailable instead of pretending to be connected.

## Flow Island layout

### Compact

![CC FLOW compact view](docs/images/trae-flow-top-demo.gif)

- **Left:** the selected compact feature. Music can take priority while media is playing.
- **Right:** the CC FLOW mascot and total attention count across clients.

### Expanded

![CC FLOW session list](docs/images/trae-flow-tsks-demo.png)
![CC FLOW session interaction](docs/images/trae-flow-tasks-talk.png)

- **Top:** a feature switcher with enablement, selection, and drag ordering.
- **Content:** the active feature or session detail, including approvals, questions, and completion results.
- **Client routing:** Claude, Codex, and TRAE counts with jump-back actions; TRAE expands to its four variants.

## Built-in features

### Music

The system now-playing panel supports Music.app, Spotify, NetEase Cloud Music, and QQ Music. Compact mode shows artwork and track information; expanded mode adds metadata, a seekable progress bar, and playback controls.

Playback data comes from the system MediaRemote framework loaded dynamically, with AppleScript fallbacks where appropriate.

### Shelf

A lightweight temporary file shelf for moving files between apps.

- Drop files from anywhere.
- View them in an expanded grid.
- Share all staged files with AirDrop.
- Shelf contents are memory-only and are cleared when CC FLOW exits.

### Custom areas and websites

Render a local HTML directory or a remote website inside the Flow Island.

![CC FLOW Mineradio](docs/images/trae-flow-mineradio.gif)
![CC FLOW custom website](docs/images/trae-flow-html-url-demo.png)

- Local HTML can publish compact hints through `window.webkit.messageHandlers.ccFlowHint.postMessage()`.
- File changes refresh the panel automatically.
- External networking is gated for local areas and can be enabled explicitly.
- Security-scoped bookmarks preserve access to user-selected directories outside the sandbox.
- Remote pages can optionally keep running after the island collapses.

### AI HOT and Mineradio

[AI HOT](https://aihot.virxact.com/) provides an embedded AI industry news feed. Mineradio uses a local compatibility bridge for NetEase Cloud Music, QQ Music, and Kugou, including compact lyrics and background playback when the Flow Island is collapsed.

### Animated pets

Spritesheet-based pets visualize idle, running, waiting, jumping, and other states. Themes follow the Codex-compatible 8-column by 9-row layout and can be loaded from `~/.cc-flow/pets/` or `~/.codex/pets/`.

Pets can stay on the Flow Island or detach to the desktop, where the mouse wheel changes their size.

## Productivity features

Every productivity feature can be enabled, disabled, selected, and ordered independently in Settings.

### File Watch

File Watch combines File Cards and natural-language metadata search while respecting explicit folder authorization.

- `Downloads` and `Documents` are suggested by default; any custom folder can be added.
- Search is limited to filename, path, File Card, OCR, and tags. Document bodies are not indexed.
- Optional AI enrichment sends at most 4,000 OCR characters and never sends an absolute file path.
- File Cards and organization suggestions are non-executable. Moving, renaming, or archiving requires explicit user confirmation and supports undo.

### Download Monitor and Browser Resources

- Chrome, Microsoft Edge, and Safari are supported.
- Settings always provides connection launchers; Download Monitor and Browser Resources show them while disconnected.
- A connection action copies the local pairing token, collapses the Flow Island, and opens the browser or Safari extension instructions.
- Extensions talk only to a loopback `127.0.0.1` endpoint and use heartbeats for current connection status.
- Download Monitor proactively opens for a new download and again when it completes.
- Browser Resources saves pages explicitly submitted by the user and does not modify browser bookmarks.
- Safari supports page capture; completed download records can still come from an authorized `Downloads` folder.

Build the local browser extensions:

```bash
./scripts/build-browser-extensions.sh
```

Load `BrowserExtensions/dist/Chrome` or `BrowserExtensions/dist/Edge` as an unpacked extension. Generate the Safari app container with `./scripts/build-safari-extension.sh`.

### Mail Assistant

Mail Assistant reads local signals from the macOS Mail app and extracts recent sender, subject, and verification-code information. It does not persist message bodies or change read state. New mail signals can proactively open the feature.

### Calendar and Reminders

- A month grid appears on the left; holidays, events, and reminders appear on the right.
- The todo list includes incomplete reminders that are overdue or due today.
- Unfinished items remind every 30 minutes.
- Checking an item marks the corresponding macOS Reminders item as completed.

### GitHub

- Uses the local `gh auth login` session first.
- Supports a Personal Access Token stored in the macOS Keychain as a fallback.
- Shows profile totals, a responsive contribution heatmap, and repositories with working GitHub links.

### Permissions and data boundaries

The Productivity Connections and Permissions & Data Sources cards report the actual status of GitHub, the selected AI provider, browser extensions, Calendar, Reminders, authorized folders, and Mail Automation.

Pairing tokens and API credentials stay in the macOS Keychain. File Watch never searches an unauthorized directory, and file organization actions never run without confirmation.

## Installation

### Download a release

1. Open [Releases](https://github.com/kilig947-alt/cc-flow/releases).
2. Download the latest DMG.
3. Drag `CC FLOW.app` into Applications.
4. Launch the app and enable the hook profiles you need.

macOS may ask for Accessibility or Apple Events permissions when you use focus and jump-back features.

> **Unsigned build note**
>
> Current GitHub Release builds use ad-hoc signing and are not notarized. If Gatekeeper blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**, right-click the app and choose **Open**, or run:
>
> ```bash
> xattr -d com.apple.quarantine /Applications/CC\ FLOW.app
> ```

### Building from source

You need macOS 14 or later and an Xcode toolchain that can build the app and the Swift 6.1 Prototype package.

```bash
git clone https://github.com/kilig947-alt/cc-flow.git
cd cc-flow

xcodebuild -project CCFlow.xcodeproj -scheme CCFlow \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CCFlow.xcodeproj -scheme CCFlow \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Create a local unsigned test package with:

```bash
./scripts/package-unsigned.sh
```

## How it works

```text
Claude Code / Codex / TRAE variants
  -> Official hook profiles
    -> CCFlowBridge (--source <claude|codex|trae>)
      -> Unix socket (/tmp/cc-flow.sock)
        -> HookSocketServer (provider + client routing)
          -> SessionStore
            -> SessionMonitor / NotchViewModel
              -> Flow Island (left: feature/session, right: counts/jump-back)
```

- Session IDs are namespaced by provider to prevent collisions.
- The default socket is `/tmp/cc-flow.sock`; runtime configuration lives in `~/Library/Application Support/cc-flow/bridge-config.json`.
- Environment variables resolve in `CC_FLOW_*`, `TRAE_FLOW_*`, then `ISLAND_*` order.
- The bridge launcher is installed at `~/.cc-flow/bin/cc-flow-bridge`.
- User-owned hooks are preserved when CC FLOW-managed entries change.

## Requirements

- macOS 14.0 or later
- A MacBook with a notch provides the most natural layout, but external displays are supported
- Claude Code, Codex, or one of the supported TRAE variants

## Testing

```bash
# Full repository regression
./scripts/test.sh

# Prototype package
swift test --package-path Prototype

# Xcode unit tests
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests
```

## Acknowledgements

CC FLOW continues the work of [ccsonicc333/trae-flow](https://github.com/ccsonicc333/trae-flow.git). We thank its maintainers and contributors for the foundation of this project.

CC FLOW builds on Dynamic Island session-monitoring ideas from [ping-island](https://github.com/erha19/ping-island), [vibe-notch](https://github.com/farouqaldori/vibe-notch), [boring.notch](https://github.com/TheBoredTeam/boring.notch), and [claude-island](https://github.com/farouqaldori/claude-island).

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
