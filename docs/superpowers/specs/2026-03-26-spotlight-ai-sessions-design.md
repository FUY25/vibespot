# VibeLight — Design Spec

**Project:** `~/Desktop/project/vibelight` (Swift/AppKit, new repo)

## Problem

Developers running multiple AI CLI sessions (Claude Code, Codex, Gemini CLI) across terminal windows suffer from:
1. **All terminals look the same** — impossible to tell which window has which task
2. **Finding the right window is slow** — Cmd+Tab and Mission Control don't help when you have 5+ identical terminal icons
3. **Context switching costs 2-5 minutes** per switch to rebuild mental context

Existing solutions (claude-squad, agent-deck) take over the full screen. The real need is a fast, lightweight search-and-jump tool.

## Product

A native macOS app with a global hotkey that brings up a floating search panel for finding and jumping to AI coding sessions. Think Spotlight/Raycast, but for your AI terminal sessions.

**Target user:** AI-heavy developers running 3+ concurrent AI CLI sessions.

### Core Flow

1. User presses global hotkey (default: `Cmd+Shift+Space`)
2. Floating panel appears centered on screen
3. User types — fuzzy search matches across session titles, projects, tools, **and full conversation transcripts**
4. Results show: project, task summary, tool (Claude/Codex), status, timestamp
5. User selects a result:
   - **Live session** → raise the terminal window
   - **Closed session** (history mode) → resume via `claude --resume <id>` or show summary

### Search Modes

**Live mode (default):** Only shows sessions currently open in a terminal window. Search matches across title, project, and full transcript content of live sessions.

**History mode (toggle via `Tab`):** Also includes closed/past sessions from JSONL history. Full-text search across all session transcripts (prompts, AI responses, tool calls, file paths, command output). Live sessions sort first.

### Search Depth

Search operates at **all levels**, not just summaries:

| Level | What's searched | Example match |
|-------|----------------|---------------|
| Title | First prompt / thread name | "fix auth bug" |
| Project | Project path + name | "terminalrail" |
| Tool | claude, codex | "codex" |
| Git | Branch name, worktree | "feat/auth" |
| **Prompts** | Every user message in the session | "JWT token expiration" |
| **AI responses** | Every assistant message | "refreshToken was never persisted" |
| **Tool calls** | Files read/edited, bash commands | "auth/token.go" |
| **Command output** | Test results, build output | "FAIL TestAuth" |

When a search matches deep content (not just the title), the result row shows the matched snippet:
```
[Claude] fix auth bug         ~/terminalrail (feat/auth)    ● Live  14:08
   ↳ "...the JWT token expires because refreshToken was never persisted..."
```

### Session Title Generation

- **Claude Code (with `sessions-index.json`):** Use the pre-computed `summary` field (e.g., "Agent Management Platform UI/UX Design Discussion") + `firstPrompt`
- **Claude Code (without index):** First user prompt from `history.jsonl` `display` field + project name
- **Codex:** `thread_name` from `session_index.jsonl` (auto-generated, already clean)
- **Fallback:** Project name + first meaningful tool action (e.g., "terminalrail — edited view.go")

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Swift/AppKit App                            │
│                                                                │
│  ┌───────────────┐  ┌───────────────┐  ┌────────────────────┐  │
│  │  File Watcher  │  │   Process     │  │   Window           │  │
│  │  (FSEvents)    │  │   Inspector   │  │   Manager          │  │
│  │                │  │   (libproc)   │  │   (AppleScript)    │  │
│  │  ~/.claude/    │  │               │  │                    │  │
│  │  ~/.codex/     │  │  CWD, process │  │  TTY→Tab mapping   │  │
│  └───────┬───────┘  └───────┬───────┘  │  Jump, raise       │  │
│          │                  │          └─────────┬──────────┘  │
│          ▼                  ▼                    │             │
│  ┌────────────────────────────────────────────────────────┐    │
│  │               SQLite + FTS5 Index                       │    │
│  │                                                        │    │
│  │  sessions table: metadata, title, project, status      │    │
│  │  transcripts FTS5: full-text over all JSONL content    │    │
│  │  terminals table: PID, CWD, process name               │    │
│  └────────────────────────┬───────────────────────────────┘    │
│                           │                                    │
│          ┌────────────────┴────────────────┐                   │
│          ▼                                 ▼                   │
│  ┌────────────────────┐  ┌──────────────────────┐              │
│  │  Floating Search   │  │  Menu Bar Icon       │              │
│  │  Panel             │  │  (session count,     │              │
│  │  (global hotkey)   │  │   status indicators) │              │
│  └────────────────────┘  └──────────────────────┘              │
└────────────────────────────────────────────────────────────────┘
```

### Components

**1. File Watcher (FSEvents)**
- Watches `~/.claude/` and `~/.codex/` directories recursively
- On change, parses new JSONL lines incrementally (track file offset per file)
- Feeds new content into SQLite FTS5 index in real-time
- FSEvents is macOS-native, efficient, battery-friendly

**2. Process Inspector (libproc)**
- Periodically scans (every 2-3 seconds) for terminal emulator processes
- Uses `proc_pidinfo` with `PROC_PIDVNODEPATHINFO` to get CWD
- Uses `proc_name` / `proc_pidpath` for process identification
- Walks process tree: terminal app → shell → foreground process
- No permissions required (same-user processes)

**3. Window Manager (AppleScript/JXA)**
- Terminal.app: uses AppleScript to get `tty`, `processes`, `busy` per tab
- iTerm2: uses AppleScript for `tty`, `contents`
- Maps session → PID → TTY → terminal tab for window jumping (verified working — see Data Sources below)
- Raises/focuses windows via `activate` + tab selection
- No Accessibility API required

**4. SQLite + FTS5 Index**
- **sessions table:** session metadata (id, title, project, tool, status, timestamps, git branch)
- **transcripts table (FTS5):** full-text index over all JSONL message content — every prompt, AI response, tool call, and command output
- Incremental: new JSONL lines are inserted as they arrive via file watcher
- Persisted to disk: enables instant startup without re-parsing all JSONL files
- Supports ranked full-text queries with snippet extraction for matched results

**5. Floating Search Panel**
- AppKit `NSPanel` with `NSWindowLevel.floating`
- No title bar, rounded corners, dark translucent background
- Auto-focused search input field
- Two-phase search: fast fuzzy match on session metadata, then FTS5 query on transcript content
- Dismisses on Escape or loss of focus

**6. Menu Bar Icon**
- `NSStatusItem` showing active session count
- Optional dot indicator when a session needs input
- Click opens the search panel

## Data Sources

### Verified Data Layout (from this machine)

#### Claude Code — Two Coexisting Storage Formats

Claude Code has evolved its storage format across versions. Both must be supported:

**Format A — With `sessions-index.json` (older sessions):**
```
~/.claude/projects/<encoded-path>/
  ├── sessions-index.json              # Pre-computed metadata index
  ├── <sessionId>/                     # Directory per session
  │   ├── subagents/agent-*.jsonl      # Subagent conversation logs
  │   └── tool-results/*.txt           # Tool output artifacts
  └── (no .jsonl files at root level)
```

`sessions-index.json` contains rich metadata per session:
```json
{
  "sessionId": "35717490-...",
  "fullPath": "/Users/.../<sessionId>.jsonl",
  "firstPrompt": "ok now illustrate using ascii graph...",
  "summary": "New Conversation",
  "messageCount": 9,
  "created": "2026-01-29T11:54:04.022Z",
  "modified": "2026-01-29T11:58:48.942Z",
  "gitBranch": "",
  "projectPath": "/Users/fuyuming/Desktop/AImanager"
}
```

**Format B — Raw JSONL files (newer sessions):**
```
~/.claude/projects/<encoded-path>/
  ├── <sessionId>.jsonl                # Full conversation (main data source)
  ├── <sessionId>/                     # Directory per session
  │   └── subagents/agent-*.jsonl      # Subagent logs
  └── (no sessions-index.json)
```

Each JSONL line contains a message with: `type`, `role`, `content`, `cwd`, `gitBranch`, `sessionId`, `timestamp`, tool calls, etc.

**Handling strategy:**
- **JSONL files are the source of truth.** Always parse these for full transcript content.
- **`sessions-index.json` is a metadata shortcut.** Use it when available for fast title/summary extraction, but never rely on it as the sole source — it can go stale or corrupt (known issue: sessions may vanish from the index while raw JSONL files remain intact).
- **Cross-validate:** If `sessions-index.json` references a session that has no corresponding JSONL file, skip it. If a JSONL file exists without an index entry, index it from the raw file.

#### Claude Code — Active Session PID Registry

```
~/.claude/sessions/<PID>.json
```

Each file maps a running process to its session:
```json
{"pid": 72611, "sessionId": "75d4bd5c-...", "cwd": "/Users/fuyuming", "startedAt": 1774506922164}
```

**This is critical for live session detection.** It provides a direct PID → sessionId mapping without guessing. Check if the PID is still alive to determine if the session is live.

#### Claude Code — Global History

```
~/.claude/history.jsonl
```

Each line: `{display, timestamp, project, sessionId}`. The `display` field is the user's prompt text. Useful for building the session list quickly, but does not contain AI responses or tool calls.

#### Codex CLI

```
~/.codex/
  ├── history.jsonl                    # {session_id, ts, text} per prompt
  ├── session_index.jsonl              # {id, thread_name, updated_at} — clean titles
  └── sessions/YYYY/MM/DD/
      └── rollout-<timestamp>-<uuid>.jsonl   # Full session with session_meta + conversation
```

Codex session JSONL includes `session_meta` payload with `cwd`, `cli_version`, `source` (cli/vscode), and the full conversation including tool calls and file operations.

### Verified: AppleScript → TTY → PID → Session Chain

The complete mapping from terminal window to AI session has been verified working:

```
Step 1: AppleScript
  Terminal.app tab → tty: "/dev/ttys005"

Step 2: Process tree
  ps -t ttys005 → PID 72611 (claude process)

Step 3: PID registry
  ~/.claude/sessions/72611.json → sessionId: "75d4bd5c-..."

Step 4: Session data
  ~/.claude/projects/<project>/<sessionId>.jsonl → full conversation
```

This chain works because Claude Code writes `~/.claude/sessions/<PID>.json` on startup, making the PID-to-session mapping trivial.

**Terminal.app window jumping (verified):**
```applescript
tell application "Terminal"
    set selected of tab j of window i to true
    activate
end tell
```

Tab selection works by matching TTY from the AppleScript API to the PID from the session registry.

### Three-Tier Data Model

**Tier 1 — AI Sessions (richest, zero setup)**

| Source | Data | Update Method |
|--------|------|---------------|
| `~/.claude/sessions/<PID>.json` | Live session PID → sessionId mapping | FSEvents watch |
| `~/.claude/projects/<path>/sessions-index.json` | Pre-computed title, summary, metadata (when available) | FSEvents watch |
| `~/.claude/projects/<path>/<sessionId>.jsonl` | Full conversation transcript | FSEvents watch |
| `~/.claude/projects/<path>/<sessionId>/subagents/*.jsonl` | Subagent conversations | FSEvents watch |
| `~/.claude/history.jsonl` | `{display, timestamp, project, sessionId}` | FSEvents watch |
| `~/.codex/session_index.jsonl` | `{id, thread_name, updated_at}` | FSEvents watch |
| `~/.codex/sessions/YYYY/MM/DD/*.jsonl` | Full session transcript | FSEvents watch |
| `~/.codex/history.jsonl` | `{session_id, ts, text}` | FSEvents watch |

**Tier 2 — Terminal Windows (medium, zero setup)**

| Source | Data | Update Method |
|--------|------|---------------|
| `CGWindowListCopyWindowInfo` | Window PID, bounds (no title without Screen Recording) | Periodic scan |
| `proc_pidinfo` | CWD, process name, TTY | Periodic scan |
| Terminal.app AppleScript | TTY, process list, busy status | On-demand |

**Tier 3 — Closed AI Sessions (searchable history)**

Same data as Tier 1 but for sessions where the PID is no longer running (checked against `~/.claude/sessions/<PID>.json` files and process liveness). Toggled into search results via `Tab`.

### Session Status Inference

| Signal | Inferred Status |
|--------|----------------|
| `~/.claude/sessions/<PID>.json` exists + PID alive | Live |
| Last JSONL message is `type: "assistant"`, no pending tool call | Waiting for input |
| Last JSONL message is `type: "user"` or tool call in progress | Running |
| PID file missing or PID not alive | Done/Closed |
| JSONL file hasn't been modified in >60s + process alive | Quiet/Idle |

~90% accurate without Accessibility API.

### Terminal Compatibility

| Terminal | AI Sessions (Tier 1) | Window Jump | Tier 2 (CWD + process) |
|----------|---------------------|-------------|----------------------|
| Terminal.app | ✅ Full (JSONL) | ✅ AppleScript (verified) | ✅ Full |
| iTerm2 | ✅ Full (JSONL) | ✅ AppleScript (needs prototyping) | ✅ CWD + process |
| Ghostty | ✅ Full (JSONL) | ⚠️ PID-based activate (app-level only) | ✅ CWD + process |
| Alacritty | ✅ Full (JSONL) | ⚠️ PID-based activate (app-level only) | ✅ CWD + process |
| kitty | ✅ Full (JSONL) | ⚠️ PID-based activate (app-level only) | ✅ CWD + process |

AI session search works identically on all terminals — data comes from JSONL files, not the terminal.

## UI & Interaction

### Global Hotkey

- Default: `Cmd+Shift+Space` (configurable in settings)
- Registered via `NSEvent.addGlobalMonitorForEvents` + `CGEvent.tapCreate`
- Toggles panel visibility

### Panel Design

- Width: ~600px, centered horizontally on active screen
- Height: dynamic, grows with results (max ~400px)
- Background: dark translucent (`NSVisualEffectView` with `.dark` material)
- No title bar, rounded corners (12px radius)
- Shadow for depth

### Key Bindings

| Key | Action |
|-----|--------|
| Type | Full-text search (metadata + transcript) |
| `↑` / `↓` | Navigate results |
| `Enter` | Jump to session (live) or resume (closed) |
| `Tab` | Toggle live/history mode |
| `Cmd+P` | Preview session detail |
| `Esc` | Dismiss panel |

### Menu Bar

- Minimal icon (could be a simple rail/track icon or just a number badge)
- Shows count of active AI sessions
- Click opens the search panel
- Optional: notification dot when a session infers "waiting for input"

## Tech Stack

- **Language:** Swift
- **UI Framework:** AppKit (not SwiftUI — need precise floating panel control)
- **Global Hotkey:** `CGEvent.tapCreate` + `NSEvent.addGlobalMonitorForEvents`
- **File Watching:** `FSEvents` (via `DispatchSource.makeFileSystemObjectSource` or raw FSEvents API)
- **Process Inspection:** `libproc` via C interop (`proc_pidinfo`, `proc_name`, `proc_pidpath`)
- **Terminal Scripting:** `NSAppleScript` for Terminal.app and iTerm2
- **Search:** SQLite FTS5 for full-text search across all session transcripts; in-memory fuzzy matching as fast first-pass on metadata
- **Persistence:** SQLite for both session index and FTS5 transcript index (fast startup, incremental updates)
- **Distribution:** Homebrew cask or `.dmg`

## Scope

### V1 — MVP

- [ ] Swift/AppKit app skeleton with menu bar icon
- [ ] Global hotkey → floating search panel
- [ ] FSEvents watcher on `~/.claude/` and `~/.codex/`
- [ ] Parse both storage formats: `sessions-index.json` (older) + raw JSONL (newer)
- [ ] Parse `~/.claude/sessions/<PID>.json` for live session detection
- [ ] SQLite FTS5 index over full session transcripts (prompts, AI responses, tool calls)
- [ ] Full-text search across title, project, tool, git branch, AND transcript content
- [ ] Matched snippet display when search hits deep content
- [ ] Live session detection (PID registry + process liveness check)
- [ ] Jump to live session window (Terminal.app AppleScript via TTY→tab mapping)
- [ ] Toggle to include closed sessions (history mode)
- [ ] Session count in menu bar
- [ ] Status inference from JSONL (waiting/running/done/idle)

### V2 — After V1 Works

- [ ] Resume closed sessions via `claude --resume <id>`
- [ ] iTerm2 window jumping support (AppleScript — needs prototyping)
- [ ] Tier 2 non-AI terminal window detection (process inspector)
- [ ] Git worktree display in result rows
- [ ] Configurable hotkey via preferences
- [ ] Notification when a session transitions to "waiting for input"
- [ ] Subagent transcript search (index `<sessionId>/subagents/*.jsonl` files)

### V3 — Future Considerations

- [ ] Gemini CLI support (verify session data location)
- [ ] Optional shell hook (`precmd`/`preexec`) for richer non-AI terminal data
- [ ] GPU-terminal window jumping (Ghostty, Alacritty, kitty) via PID-based activation
- [ ] LLM-generated session titles (API call to summarize first few messages)
- [ ] Session timeline view (expanded detail showing prompts, edits, commands)

### Explicitly Out of Scope

- No Accessibility API (not needed — JSONL + proc_pidinfo + AppleScript covers all use cases)
- No Screen Recording permission
- No PTY wrapper (existing TerminalRail approach — replaced by JSONL file watching)
- No Claude Desktop app path (`~/Library/Application Support/Claude/`) — this product targets CLI users
- No cross-platform (macOS only for now)
- No full-screen TUI (this is a floating panel, not a terminal app)

## Relationship to Existing TerminalRail Code

This is a **product pivot**, not an iteration. The existing Go/Bubble Tea codebase (PTY wrapper, SQLite session store, TUI rail, creature system) is not reused. The new app:

- Is written in Swift, not Go
- Reads existing JSONL files instead of wrapping processes in a PTY
- Shows a floating Spotlight-like panel instead of a persistent rail window
- Requires zero user behavior change (no `tr claude "..."` launcher)

The existing codebase is archived. The new project lives at `~/Desktop/project/vibelight`.

## Open Questions

1. ~~**Product name**~~ — Resolved: **VibeLight**.
2. **Gemini CLI** — Where does it store session data? Needs verification.
3. **Window jumping for GPU terminals** — `NSRunningApplication.activate()` can bring the app to front, but selecting a specific tab requires terminal-specific APIs. May need to fall back to "bring app to front" without tab selection for Ghostty/Alacritty/kitty.
4. **Multiple monitors** — Should the panel appear on the active monitor or always on the primary?
5. **FTS5 index size** — For heavy users with thousands of sessions, the FTS5 index could grow large. May need a retention policy (e.g., only index last 90 days of history by default).
