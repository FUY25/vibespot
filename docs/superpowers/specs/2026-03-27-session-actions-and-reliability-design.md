# Session Actions & Reliability — Design Spec

## Goal

Make VibeLight fully functional for both Claude and Codex: resume closed sessions, start new sessions, detect live Codex sessions, and guarantee 100% hotkey reliability.

## Scope

Five fixes in one spec — all small, all related to "pressing a hotkey and doing something useful":

1. **Hotkey reliability** — 100% first-press success rate
2. **Codex live session detection** — detect running Codex processes
3. **Resume closed sessions** — ENTER on a closed session opens Terminal and resumes it
4. **New session launcher** — type "new" to start a fresh Claude or Codex session
5. **Codex git branch** — stop hardcoding empty string

---

## 1. Hotkey Reliability

### Problem

The Cmd+Shift+Space hotkey often requires 2 presses. The background scan fix (startup perf Task 3) moved heavy indexing off MainActor, but the hotkey is still unreliable.

### Root Cause

The event tap is registered as `.defaultTap` (can consume events). macOS imposes strict latency requirements on default taps and will disable them via `tapDisabledByTimeout` if the callback takes too long or the system is under load. The current code re-enables the tap when it detects `tapDisabledByTimeout`, but by then the keypress is lost.

Additionally, VibeLight runs as an `.accessory` app (no dock icon). When the app isn't the active app, `NSApp.activate(ignoringOtherApps: true)` in `show()` may cause a brief activation dance where macOS sends a deactivation notification, triggering `hidesOnDeactivate` and hiding the panel immediately after it appears.

### Fix

Two changes:

**A. Switch from CGEventTap to Carbon RegisterEventHotKey.**

`RegisterEventHotKey` is the standard macOS API for global hotkeys. It doesn't have the timeout/disable problem because it's not intercepting the full event stream — it registers a specific key combination with the system. Apps like Spotlight, Alfred, and Raycast all use this approach.

Replace `HotkeyManager`'s event tap with:
- `RegisterEventHotKey(kVK_Space, cmdKey | shiftKey, ...)` to register
- `UnregisterEventHotKey(...)` to unregister
- Install a Carbon event handler for `kEventHotKeyPressed`

This eliminates the `tapDisabledByTimeout` problem entirely. It also removes the Accessibility permission requirement (event taps need it; `RegisterEventHotKey` does not).

**B. Fix the activation race.**

In `show()`, ensure activation completes before showing the panel:
- Call `NSApp.activate(ignoringOtherApps: true)` first
- Then `panel.makeKeyAndOrderFront(nil)`
- Set `panel.hidesOnDeactivate = false` temporarily during the show sequence, re-enable it after a short delay (e.g., next run loop cycle)

Or simpler: set `panel.hidesOnDeactivate = false` permanently and handle deactivation manually via `NSApplication.didResignActiveNotification` — this gives us full control over when the panel hides.

---

## 2. Codex Live Session Detection

### Problem

`LiveSessionRegistry` only scans `~/.claude/sessions/*.json` for Claude PID files. Codex doesn't write PID files, so live Codex sessions are never detected.

### Fix

Add a `scanCodexProcesses()` method to `LiveSessionRegistry`:

1. Run `ps -axo pid,comm` and filter for processes where `comm` ends with `codex`
2. For each live PID, get its working directory via `lsof -d cwd -Fn -p <pid>` (returns the cwd as a `n/path/to/dir` line)
3. Match the PID+CWD to the most recent codex session in that directory from the session index
4. Return `LiveSession` entries with `pid`, `sessionId`, `cwd`, `isAlive: true`

The session matching uses the `threads` table in `~/.codex/state_5.sqlite`:
- Query: `SELECT id FROM threads WHERE cwd = ? ORDER BY updated_at DESC LIMIT 1`
- This gives us the session ID for a given CWD

Alternatively, skip the state DB and match by finding the most recently modified `.jsonl` file whose parsed `session_meta.cwd` matches the process CWD. But the state DB is faster and already has the mapping.

**Chosen approach:** Use process scanning (`ps`) + CWD lookup (`lsof`) + state DB matching. This is reliable and doesn't require parsing session files.

`LiveSessionRegistry.scan()` returns both Claude and Codex live sessions combined.

---

## 3. Resume Closed Sessions

### Problem

ENTER on a closed session calls `WindowJumper.jumpToSession()` which silently returns for non-live sessions. The UI shows "↩ Resume" but nothing happens.

### Fix

**A. Add `TerminalLauncher` utility.**

New file: `Sources/VibeLight/Window/TerminalLauncher.swift`

Single method:
```
static func launch(command: String, directory: String)
```

Uses AppleScript:
```applescript
tell application "Terminal"
    do script "cd <escaped-dir> && <command>"
    activate
end tell
```

This opens a new Terminal.app tab/window with the command running.

**B. Wire resume into `activateSelectedResult`.**

In `SearchPanelController.activateSelectedResult()`, the `onSelect` callback currently calls `WindowJumper.jumpToSession()`. Change the flow:

- If `result.status == "live"` and `result.pid != nil`: call `WindowJumper.jumpToSession()` (existing behavior — switch to window)
- If `result.status != "live"` (closed session): call `TerminalLauncher.launch()` with the appropriate resume command

Resume commands:
- Claude: `claude --resume <session-id>`
- Codex: `codex resume <session-id>`

The directory is `result.project` (the session's project/CWD).

**C. Update `onSelect` callback signature.**

Currently `onSelect: ((SearchResult) -> Void)?`. Change the `AppDelegate` wiring so it handles both live and closed:

```swift
panelController.onSelect = { result in
    if result.status == "live" {
        WindowJumper.jumpToSession(result)
    } else {
        let command: String
        switch result.tool {
        case "codex":
            command = "codex resume \(result.sessionId)"
        default:
            command = "claude --resume \(result.sessionId)"
        }
        TerminalLauncher.launch(command: command, directory: result.project)
    }
}
```

This moves the live/closed branching out of `WindowJumper` (which should only handle window switching) into the `AppDelegate` callback where it belongs.

---

## 4. New Session Launcher

### Problem

No way to start a fresh session from VibeLight.

### Fix

**A. Detect "new" query.**

In `SearchPanelController.refreshResults()`, after getting search results, check if the query starts with "new" (case-insensitive). If so, prepend action rows.

**B. Action rows.**

Model action rows as `SearchResult` values with a sentinel status:
- `status = "action"`
- `sessionId = "new-claude"` or `"new-codex"`
- `tool = "claude"` or `"codex"`
- `title = "New Claude session"` or `"New Codex session"`
- `project = <most-recent-project-path>`
- `projectName = <most-recent-project-name>`

To find the most recent project: query `SELECT project, project_name FROM sessions ORDER BY last_activity_at DESC LIMIT 1`. Add a `mostRecentProject()` method to `SessionIndex` for this.

If no sessions exist, fall back to `$HOME`.

**C. Action hint for action rows.**

In `updateActionHint()`, when the selected result has `status == "action"`:
- Show `"↩ Launch"` instead of `"↩ Resume"` or `"↩ Switch"`

**D. Handle action row selection.**

In the `onSelect` callback, check for `status == "action"`:
- `sessionId == "new-claude"`: `TerminalLauncher.launch(command: "claude", directory: project)`
- `sessionId == "new-codex"`: `TerminalLauncher.launch(command: "codex", directory: project)`

**E. Action rows should appear mixed with search results.**

When query starts with "new", action rows go at the top, followed by any matching search results (e.g., sessions with "new" in their title).

---

## 5. Codex Git Branch

### Problem

In `Indexer.indexCodexSessionFile()`, `gitBranch` is hardcoded to `""` (line 264). The codex state DB (`~/.codex/state_5.sqlite` → `threads` table) has `git_branch` available.

### Fix

Since we're already reading the codex state DB for live session matching (feature #2), add git branch lookup:

- When indexing a codex session, look up `git_branch` from the `threads` table by session ID
- If found, pass it to `upsertSession()` instead of `""`
- If not found, fall back to `""`

This can be done by preloading a `[sessionId: gitBranch]` map from the state DB at the start of `scanCodexSessions()`, similar to how `loadCodexTitleMap()` works.

**Shared utility:** Features #2 and #5 both read `~/.codex/state_5.sqlite`. Create a single `CodexStateDB` helper (or add methods to `CodexParser`) that provides:
- `sessionIdByCwd(cwd:) -> String?` (for live detection)
- `gitBranchBySessionId() -> [String: String]` (for indexing)

This avoids opening the same DB in two places.

---

## File Map

| File | Action | Features |
|---|---|---|
| `Sources/VibeLight/HotkeyManager.swift` | Rewrite | #1 (Carbon hotkey) |
| `Sources/VibeLight/Data/LiveSessionRegistry.swift` | Modify | #2 (codex process scan) |
| `Sources/VibeLight/Window/TerminalLauncher.swift` | Create | #3, #4 (shared launcher) |
| `Sources/VibeLight/Window/WindowJumper.swift` | Minor | #3 (remove dead-code guard) |
| `Sources/VibeLight/App/AppDelegate.swift` | Modify | #3 (wire onSelect branching) |
| `Sources/VibeLight/UI/SearchPanelController.swift` | Modify | #4 (action rows), #1 (activation fix) |
| `Sources/VibeLight/Data/SessionIndex.swift` | Modify | #4 (mostRecentProject query) |
| `Sources/VibeLight/Watchers/Indexer.swift` | Modify | #5 (codex git branch) |
| Tests | Add | All features |

---

## Out of Scope

- Supporting terminals other than Terminal.app
- Codex resume with `--cwd` flag (codex resume uses the session's original CWD)
- Custom hotkey configuration
- Gemini CLI support (icon exists but no indexing/detection)
