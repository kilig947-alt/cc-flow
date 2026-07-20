# README Productivity Gallery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six supplied CC FLOW screenshots to the repository and present them contextually in both Chinese and English README files.

**Architecture:** Store immutable PNG assets under `docs/images/` with semantic names. Add the compact screenshot beside the existing compact-state documentation and add an HTML-table gallery beside each README's productivity section, sharing the same assets and ordering.

**Tech Stack:** Markdown, HTML table markup, PNG assets, shell validation.

## Global Constraints

- Preserve the original PNG bytes without cropping or recompression.
- Update `README.md` and `README.en.md` with equivalent structure and localized copy.
- Do not remove existing README screenshots.
- Do not modify application code or unrelated dirty files.

---

### Task 1: Add screenshot assets and bilingual README galleries

**Files:**
- Create: `docs/images/flow-island-compact-usage.png`
- Create: `docs/images/productivity-account-usage.png`
- Create: `docs/images/productivity-system-monitor.png`
- Create: `docs/images/productivity-calendar.png`
- Create: `docs/images/productivity-github.png`
- Create: `docs/images/productivity-file-watch.png`
- Modify: `README.md`
- Modify: `README.en.md`

**Interfaces:**
- Consumes: the six supplied clipboard PNG paths recorded in the approved design specification.
- Produces: stable repository-relative image URLs referenced by both README files.

- [ ] **Step 1: Copy the original PNG files**

Use `cp` to map each supplied clipboard file to the semantic filename listed above. Do not run an image encoder.

- [ ] **Step 2: Verify image integrity before editing Markdown**

Run:

```bash
file docs/images/flow-island-compact-usage.png docs/images/productivity-*.png
sips -g pixelWidth -g pixelHeight docs/images/flow-island-compact-usage.png docs/images/productivity-*.png
```

Expected: all six files report PNG image data and positive width/height values.

- [ ] **Step 3: Update the Chinese README**

After the existing compact-state GIF, add a centered compact usage image with Chinese alternative text and a one-sentence description. Immediately after the `## 生产力功能` introduction, add `### 生产力功能预览` with an HTML table pairing 账号用量/系统监控, 日历/GitHub, and a full-width File Watch image.

- [ ] **Step 4: Update the English README**

Mirror the Chinese placement using `### Productivity Feature Preview`, localized titles, natural English alt text, and the same image paths and ordering.

- [ ] **Step 5: Validate paths and formatting**

Run:

```bash
for image in flow-island-compact-usage productivity-account-usage productivity-system-monitor productivity-calendar productivity-github productivity-file-watch; do test -f "docs/images/$image.png"; done
rg -n "flow-island-compact-usage|productivity-(account-usage|system-monitor|calendar|github|file-watch)" README.md README.en.md
git diff --check
```

Expected: every image appears in both README files where applicable, all files exist, and `git diff --check` exits successfully.
