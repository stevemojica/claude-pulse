# Claude Pulse Feature Expansion Design

**Date:** 2026-04-02
**Status:** Approved
**Scope:** 5 independent feature tracks to enhance Claude Pulse's session monitoring, interaction, and update capabilities

## Overview

Claude Pulse is a native macOS menu bar app (~4K lines Swift, zero external dependencies) that monitors AI agent sessions and API usage. This spec adds five features inspired by competitive analysis while maintaining Claude Pulse's open-source, zero-dependency philosophy.

## Feature 1: Configurable Notch/Bottom Bar Positioning

### Goal
Let users position the command bar at the top of the screen (notch area on MacBooks) or bottom, via a settings toggle.

### Files Changed
- `ScreenLayout.swift`
- `SettingsView.swift`
- `CommandBarWindow.swift`

### Design

**New setting:** `barPosition` enum with `.top` and `.bottom` cases, stored in UserDefaults. Default: `.bottom` (preserves current behavior).

**ScreenLayout changes:**
- Current layout hardcodes `y = visibleFrame.maxY - height - 4` (bottom).
- Add a `position` parameter to all frame calculations.
- Top position: `y = visibleFrame.maxY - height - 4` on external displays, or `y = screenFrame.maxY - notchHeight - height - 4` on notched displays.
- Reuse existing notch detection: `(screenFrame.maxY - visibleFrame.maxY) > 24`.
- All three states (strip, preview, dashboard) get top variants. Strip and preview anchor at top edge. Dashboard drops down from top.

**CommandBarWindow changes:**
- Read position preference on launch and on settings change.
- Animate frame transition when user toggles position.
- Dashboard expands downward (from top) or upward (from bottom) depending on position.

**Settings UI:**
- New "Bar Position" picker: "Top (Notch area)" / "Bottom".
- Takes effect immediately on change.

---

## Feature 2: Rich Permission UI

### Goal
Replace the compact permission card with a full-detail view showing complete tool arguments with syntax highlighting, diffs, and formatted code.

### Files Changed
- `ClaudePulseBridge/main.swift`
- `SessionProtocol.swift`
- `AgentSession.swift`
- New: `PermissionDetailView.swift`
- `CommandBarDashboardView.swift`
- `CommandBarPreviewView.swift`

### Design

**Bridge changes:**
- Remove the 200-char truncation on `tool_input`. Forward full arguments JSON as a string.
- Extract `file_path` when tool is `Read` or `Edit` for filename headers.
- Increase protocol max message size from 64KB to 256KB.

**PermissionPrompt model update:**
- Add `toolInput: [String: Any]?` for raw structured arguments.
- Keep existing `arguments: String?` as serialized fallback.

**New PermissionDetailView** renders based on tool type:
- **Bash**: command in monospace code block with shell syntax coloring (keywords, strings, pipes).
- **Read/Edit/Write**: filename header + file content with line numbers. Edit shows old/new with red/green diff highlighting.
- **Grep/Glob**: pattern + path in styled fields.
- **WebFetch**: URL displayed as a link.
- **Other tools**: JSON-formatted arguments in a code block.
- Wrapped in `ScrollView` with max height 300px.
- Header bar: SF Symbol tool icon + tool name. Allow/Deny buttons pinned at bottom.

**Integration:**
- `CommandBarPreviewView` uses `PermissionDetailView` instead of compact card.
- `CommandBarDashboardView` session cards show inline expandable permission detail.
- Dashboard auto-scrolls to the permission-requesting session.

---

## Feature 3: Interactive Q&A with Context

### Goal
When Claude Code asks a question (AskUserQuestion), show the question with conversation context, clickable option buttons, and a free text input field. Send the answer back via socket.

### Files Changed
- `ClaudePulseBridge/main.swift`
- `SessionProtocol.swift`
- `SocketServer.swift`
- `AgentSession.swift`
- New: `QuestionView.swift`
- `CommandBarDashboardView.swift`
- `CommandBarPreviewView.swift`

### Design

**Bridge changes:**
- For `Notification` events with `idle_prompt` type, extract: `question` (full text), `options` (array of suggested answers if present), `context` (current task description).

**Protocol additions:**
- New `SessionMessage` type: `question` with fields `question`, `options: [String]?`, `context: String?`.
- New `SessionResponse` type: `questionResponse` with field `answer: String`.
- Socket keeps connection open (same pattern as permission relay). Bridge blocks reading from fd, gets the answer, writes to stdout for the hook.

**AgentSession model update:**
- Replace `question: String?` with `questionPrompt: QuestionPrompt?`.
- `QuestionPrompt` struct: `question: String`, `options: [String]`, `context: String?`, `responseCallback: @Sendable (String) -> Void`.

**New QuestionView layout:**
- **Context section** (top): gray card showing "Claude was: {currentTask}".
- **Question section** (middle): question text with markdown rendering (bold, code, lists).
- **Options section**: each option as a styled button, vertical layout. Tapping sends answer immediately.
- **Free text section** (bottom): TextField with placeholder "Type a custom answer..." + Send button. Send disabled when empty and no option selected.

**SessionManager additions:**
- `resolveQuestion(id: UUID, answer: String)` — calls callback, clears prompt, resets status to `.working`.

**Integration:**
- Preview auto-expands on question arrival (same as permissions).
- Dashboard shows QuestionView inline in session card.
- Sound plays on question arrival (reuse existing attention sound).

---

## Feature 4: Precise Terminal Jumping

### Goal
Click a session to jump to the exact terminal window. Prioritize Warp, Ghostty/Cmux, and Terminal.app.

### Files Changed
- `TerminalJumper.swift`
- `AgentSession.swift`

### Design

**Terminal detection improvements:**
- Enhance process tree walker to recognize:
  - **Warp**: bundle ID `dev.warp.Warp-Stable`
  - **Ghostty/Cmux**: bundle ID `com.mitchellh.ghostty` or process name containing `ghostty`/`cmux`
  - **Terminal.app**: already recognized
- Store detected terminal in `TerminalInfo.bundleIdentifier` from both socket and log watcher sessions.

**Per-terminal activation strategy:**

| Terminal | Strategy |
|----------|----------|
| **Warp** | PID-based `NSRunningApplication` activation. Investigate `warp://` URL scheme for session targeting. Fallback: activate app (brings recent window). |
| **Ghostty/Cmux** | PID-based activation via process tree walk. `NSRunningApplication.activate()` to bring to front. Cmux wrapping Ghostty: PID walk finds Ghostty parent. |
| **Terminal.app** | Existing AppleScript, improved to match by TTY for exact tab targeting. |

**General improvements:**
- Accessibility API as secondary strategy: `AXUIElementCreateApplication` to target windows by title matching (match working directory in window title).
- Visual feedback: briefly flash session card border green on successful jump, red on failure.
- Log jump failures for debugging.

**Priority order:** Warp > Ghostty/Cmux > Terminal.app improvements.

---

## Feature 5: Self-Updating Binary

### Goal
One-click update from within the app. No browser, no DMG, no manual steps. Zero external dependencies (no Sparkle).

### Files Changed
- `UpdateManager.swift`
- `CommandBarDashboardView.swift`
- `SettingsView.swift`

### Design

**Update flow:**
1. **Check** — existing GitHub Releases API stays the same. Runs on launch (if auto-check enabled) + manual button.
2. **Download** — on user click, download release asset to temp directory via `URLSession` with progress tracking.
3. **Verify** — compare file size against GitHub release asset size. If release body contains `SHA256: {hash}`, verify checksum.
4. **Replace** — overwrite both install locations:
   - `~/Applications/Claude Pulse.app/Contents/MacOS/ClaudePulse`
   - `~/.local/bin/claude-pulse` (if exists)
   - Set executable permissions `0o755`.
5. **Relaunch** — spawn background shell script that waits 1 second then runs `open ~/Applications/Claude\ Pulse.app`. Exit current process via `NSApplication.shared.terminate(nil)`.

**UI changes:**
- Dashboard banner: "Update available: v2.0 -> v2.1" with "Update Now" button.
- During download: replace button with progress bar + percentage.
- On completion: banner shows "Restarting..." then app relaunches.
- On failure: error message with "Retry" button.
- Settings: "Check for Updates" button + "Auto-check on launch" toggle (default: on).

**Edge cases:**
- Dev mode (running from `.build/release/`): skip app bundle replacement, only update `~/.local/bin`.
- Download failure: clean up temp file, don't touch existing binaries.
- Binary in use: writing over it is safe on macOS. Running process keeps its file descriptor; new launches use new binary.

---

## Architecture Notes

### Independence
All 5 features are independent. They can be built and shipped in any order without blocking each other.

### Zero Dependencies Maintained
No external packages added. Self-updater is built on Foundation's `URLSession`. All UI is SwiftUI + AppKit. Terminal jumping uses built-in frameworks (Accessibility, NSRunningApplication, AppleScript via NSAppleScript).

### Protocol Max Message Size
Increased from 64KB to 256KB to support full tool arguments in permission view. This is the only cross-cutting change.

### Testing Strategy
- Each feature can be tested independently.
- Permission UI: trigger with any Claude Code tool call.
- Q&A: trigger with AskUserQuestion in a Claude session.
- Terminal jump: run Claude Code in each target terminal.
- Self-updater: create a test GitHub release with a dummy binary.
- Bar positioning: toggle in settings, verify on both notched and external displays.
