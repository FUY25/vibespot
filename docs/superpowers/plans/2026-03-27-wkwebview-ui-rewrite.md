# WKWebView UI Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace VibeLight's AppKit UI rendering layer with a WKWebView panel that matches DESIGN.md pixel-perfectly, fix duplicate Codex sessions, and silence CodexStateDB error spam.

**Architecture:** The native Swift shell (hotkey, indexing, parsing, window management) stays untouched. A new `WebBridge` handles Swift↔JS communication. The panel UI is rendered as HTML/CSS/JS inside a WKWebView hosted by the existing NSPanel. Arrow-key navigation runs entirely in JS for 60fps responsiveness.

**Tech Stack:** Swift 6 / AppKit / WKWebView / WebKit / HTML / CSS / JavaScript / SQLite3

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/VibeLight/UI/WebBridge.swift` | WKScriptMessageHandler — receives JS messages, calls back into SearchPanelController |
| `Sources/VibeLight/Resources/Web/panel.html` | Panel HTML structure — search bar, separator, results container |
| `Sources/VibeLight/Resources/Web/panel.css` | All DESIGN.md tokens as CSS custom properties, animations, row states |
| `Sources/VibeLight/Resources/Web/panel.js` | Search input handling, keyboard navigation, result rendering, ghost suggestions |
| `Tests/VibeLightTests/WebBridgeTests.swift` | Tests for message parsing and response serialization |
| `Tests/VibeLightTests/PIDDeduplicationTests.swift` | Tests for duplicate session dedup logic |
| `Tests/VibeLightTests/CodexStateDBThrottleTests.swift` | Tests for error caching and log throttling |

### Modified Files
| File | Changes |
|------|---------|
| `Sources/VibeLight/UI/SearchPanelController.swift` | Replace all AppKit view setup with WKWebView host; simplify to bridge-based communication |
| `Sources/VibeLight/Watchers/Indexer.swift` | Add PID-based dedup pass in `refreshLiveSessions()` |
| `Sources/VibeLight/Data/CodexStateDB.swift` | Add failure timestamp caching and log throttling |
| `Package.swift` | Add WebKit framework import |

### Deleted Files
| File | Replaced By |
|------|------------|
| `Sources/VibeLight/UI/ResultRowView.swift` | HTML/CSS rows in panel.html/panel.css |
| `Sources/VibeLight/UI/ResultsTableView.swift` | HTML results container in panel.html |
| `Sources/VibeLight/UI/DesignTokens.swift` | CSS custom properties in panel.css |
| `Sources/VibeLight/UI/SearchField.swift` | HTML input element in panel.html + ghost suggestion in panel.js |
| `Sources/VibeLight/UI/ToolIcon.swift` | `<img>` tags referencing bundled PNGs via `panel.js` |

---

### Task 1: CodexStateDB Error Caching and Log Throttling

**Files:**
- Modify: `Sources/VibeLight/Data/CodexStateDB.swift`
- Create: `Tests/VibeLightTests/CodexStateDBThrottleTests.swift`

- [ ] **Step 1: Write failing tests for error caching**

```swift
// Tests/VibeLightTests/CodexStateDBThrottleTests.swift
import Testing
@testable import VibeLight

@Suite("CodexStateDB throttle tests")
struct CodexStateDBThrottleTests {
    @Test("sessionIdByCwd returns nil without spamming when DB missing")
    func missingDBReturnsNil() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        let result1 = db.sessionIdByCwd("/some/path")
        let result2 = db.sessionIdByCwd("/other/path")
        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("gitBranchMap returns empty without spamming when DB missing")
    func missingDBReturnsEmpty() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        let result1 = db.gitBranchMap()
        let result2 = db.gitBranchMap()
        #expect(result1.isEmpty)
        #expect(result2.isEmpty)
    }

    @Test("repeated calls within cooldown skip DB open")
    func cooldownSkipsRepeatedAttempts() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        // First call sets the failure timestamp
        _ = db.sessionIdByCwd("/a")
        // Second call within 30s should return nil immediately without attempting open
        _ = db.sessionIdByCwd("/b")
        // We verify this doesn't crash or spam — the test passing is sufficient
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter CodexStateDBThrottleTests 2>&1 | head -30`
Expected: Compilation error — `CodexStateDB` is a struct with no mutable state for caching.

- [ ] **Step 3: Add failure caching and log throttling to CodexStateDB**

Replace `Sources/VibeLight/Data/CodexStateDB.swift` with:

```swift
import Foundation
import SQLite3

final class CodexStateDB {
    let path: String
    private var lastFailureTime: Date?
    private var lastLogTime: Date?
    private static let cooldownInterval: TimeInterval = 30
    private static let logThrottleInterval: TimeInterval = 60

    init(path: String) {
        self.path = path
    }

    init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("state_5.sqlite")
            .path
        self.init(path: path)
    }

    func sessionIdByCwd(_ cwd: String) -> String? {
        guard shouldAttemptOpen() else { return nil }

        return withReadOnlyDatabase { db in
            let sql = """
            SELECT id
            FROM threads
            WHERE cwd = ?1
            ORDER BY updated_at DESC
            LIMIT 1
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                logSQLiteError(db, context: "prepare sessionIdByCwd")
                return nil
            }
            defer { sqlite3_finalize(statement) }

            guard sqlite3_bind_text(statement, 1, (cwd as NSString).utf8String, -1, Self.transientDestructor) == SQLITE_OK else {
                logSQLiteError(db, context: "bind sessionIdByCwd")
                return nil
            }

            let rc = sqlite3_step(statement)
            guard rc == SQLITE_ROW else {
                if rc != SQLITE_DONE {
                    logSQLiteError(db, context: "step sessionIdByCwd", code: rc)
                }
                return nil
            }
            guard let id = sqlite3_column_text(statement, 0) else {
                return nil
            }

            return String(cString: id)
        }
    }

    func gitBranchMap() -> [String: String] {
        guard shouldAttemptOpen() else { return [:] }

        return withReadOnlyDatabase { db in
            let sql = """
            SELECT id, git_branch
            FROM threads
            WHERE git_branch IS NOT NULL
              AND TRIM(git_branch) <> ''
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                logSQLiteError(db, context: "prepare gitBranchMap")
                return [:]
            }
            defer { sqlite3_finalize(statement) }

            var branches: [String: String] = [:]

            while true {
                let rc = sqlite3_step(statement)
                if rc == SQLITE_DONE {
                    break
                }
                if rc != SQLITE_ROW {
                    logSQLiteError(db, context: "step gitBranchMap", code: rc)
                    break
                }

                guard let idText = sqlite3_column_text(statement, 0),
                      let branchText = sqlite3_column_text(statement, 1)
                else {
                    continue
                }

                branches[String(cString: idText)] = String(cString: branchText)
            }

            return branches
        } ?? [:]
    }

    private func shouldAttemptOpen() -> Bool {
        if let lastFailure = lastFailureTime {
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed < Self.cooldownInterval {
                return false
            }
        }
        return true
    }

    private func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) -> T?) -> T? {
        guard FileManager.default.fileExists(atPath: path) else {
            lastFailureTime = Date()
            return nil
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)

        guard rc == SQLITE_OK, let db = handle else {
            lastFailureTime = Date()
            if let handle {
                logSQLiteError(handle, context: "open read-only database", code: rc)
                sqlite3_close_v2(handle)
            }
            return nil
        }

        // Reset failure tracking on successful open
        lastFailureTime = nil

        if sqlite3_busy_timeout(db, 300) != SQLITE_OK {
            logSQLiteError(db, context: "configure busy timeout")
        }

        defer {
            let closeRC = sqlite3_close_v2(db)
            if closeRC != SQLITE_OK {
                logSQLiteError(db, context: "close read-only database", code: closeRC)
            }
        }
        return operation(db)
    }

    private func logSQLiteError(_ db: OpaquePointer?, context: String, code: Int32? = nil) {
        let now = Date()
        if let lastLog = lastLogTime, now.timeIntervalSince(lastLog) < Self.logThrottleInterval {
            return
        }
        lastLogTime = now

        let rc = code ?? sqlite3_errcode(db)
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        print("CodexStateDB: \(context) failed (\(rc)): \(message)")
    }

    // Equivalent to SQLITE_TRANSIENT for sqlite3_bind_text.
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
```

Key changes from original:
- Changed from `struct` to `final class` (needs mutable state for caching)
- Added `lastFailureTime` — caches failed open attempts for 30 seconds
- Added `lastLogTime` — throttles error logging to once per 60 seconds
- `shouldAttemptOpen()` — skips DB access if within cooldown period
- `withReadOnlyDatabase` — sets `lastFailureTime` on file-not-found or open failure, resets on success

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter CodexStateDBThrottleTests 2>&1 | tail -10`
Expected: All 3 tests pass.

- [ ] **Step 5: Run existing CodexStateDB tests to check for regressions**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter CodexStateDBTests 2>&1 | tail -10`
Expected: All existing tests pass. If any fail due to the struct→class change, update them (the API is unchanged, only the value semantics changed).

- [ ] **Step 6: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/Data/CodexStateDB.swift Tests/VibeLightTests/CodexStateDBThrottleTests.swift
git commit -m "fix: add failure caching and log throttling to CodexStateDB"
```

---

### Task 2: PID-Based Duplicate Session Deduplication

**Files:**
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Create: `Tests/VibeLightTests/PIDDeduplicationTests.swift`

- [ ] **Step 1: Write failing test for PID dedup**

```swift
// Tests/VibeLightTests/PIDDeduplicationTests.swift
import Testing
import Foundation
@testable import VibeLight

@Suite("PID deduplication tests")
struct PIDDeduplicationTests {
    @Test("deduplicateLiveSessions keeps only newest session per PID")
    func deduplicatesByPID() throws {
        let now = Date()
        let older = now.addingTimeInterval(-60)
        let newest = now.addingTimeInterval(-5)

        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("session-old", 1234, older),
            ("session-new", 1234, newest),
            ("session-other", 5678, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(staleIDs == ["session-old"])
    }

    @Test("deduplicateLiveSessions returns empty when no shared PIDs")
    func noSharedPIDs() throws {
        let now = Date()
        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("session-a", 111, now),
            ("session-b", 222, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(staleIDs.isEmpty)
    }

    @Test("deduplicateLiveSessions handles three sessions sharing a PID")
    func threeSessionsSamePID() throws {
        let now = Date()
        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("oldest", 1234, now.addingTimeInterval(-120)),
            ("middle", 1234, now.addingTimeInterval(-60)),
            ("newest", 1234, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(Set(staleIDs) == Set(["oldest", "middle"]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter PIDDeduplicationTests 2>&1 | head -20`
Expected: Compilation error — `Indexer.sessionIDsToCloseByPID` does not exist.

- [ ] **Step 3: Add the static dedup method to Indexer**

In `Sources/VibeLight/Watchers/Indexer.swift`, add this method inside the `Indexer` class (after the `// MARK: - Live sessions` section):

```swift
    /// Given a list of (sessionId, pid, startedAt) tuples, returns session IDs
    /// that should be marked "closed" because a newer session shares their PID.
    static func sessionIDsToCloseByPID(
        sessions: [(sessionId: String, pid: Int, startedAt: Date)]
    ) -> [String] {
        var byPID: [Int: [(sessionId: String, startedAt: Date)]] = [:]
        for s in sessions {
            byPID[s.pid, default: []].append((s.sessionId, s.startedAt))
        }

        var staleIDs: [String] = []
        for (_, group) in byPID where group.count > 1 {
            let sorted = group.sorted { $0.startedAt > $1.startedAt }
            for stale in sorted.dropFirst() {
                staleIDs.append(stale.sessionId)
            }
        }
        return staleIDs
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter PIDDeduplicationTests 2>&1 | tail -10`
Expected: All 3 tests pass.

- [ ] **Step 5: Wire the dedup into refreshLiveSessions()**

In `Sources/VibeLight/Watchers/Indexer.swift`, modify `refreshLiveSessions()` to add a dedup pass after the existing live/closed logic:

Replace the existing `refreshLiveSessions()` method with:

```swift
    private func refreshLiveSessions() {
        let liveSessions = LiveSessionRegistry.scan()
        let aliveSessionsByID = Dictionary(
            liveSessions
                .filter(\.isAlive)
                .map { ($0.sessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let aliveSessionIDs = Set(
            liveSessions
                .filter(\.isAlive)
                .map(\.sessionId)
        )

        for sessionId in aliveSessionIDs {
            try? sessionIndex.updateRuntimeState(
                sessionId: sessionId,
                status: "live",
                pid: aliveSessionsByID[sessionId]?.pid
            )
        }

        let indexedLiveSessionIDs = (try? sessionIndex.liveSessionIDs()) ?? []
        for sessionId in indexedLiveSessionIDs.subtracting(aliveSessionIDs) {
            try? sessionIndex.updateRuntimeState(sessionId: sessionId, status: "closed", pid: nil)
        }

        // Dedup: when multiple live sessions share a PID, close all but the newest
        deduplicateSharedPIDSessions(aliveSessionsByID: aliveSessionsByID)
    }

    private func deduplicateSharedPIDSessions(aliveSessionsByID: [String: LiveSession]) {
        // Build (sessionId, pid, startedAt) tuples for alive sessions
        var tuples: [(sessionId: String, pid: Int, startedAt: Date)] = []
        for (sessionId, liveSession) in aliveSessionsByID {
            let startedAt: Date
            if let rows = try? sessionIndex.search(query: "", liveOnly: true) {
                startedAt = rows.first(where: { $0.sessionId == sessionId })?.startedAt ?? .distantPast
            } else {
                startedAt = .distantPast
            }
            tuples.append((sessionId, liveSession.pid, startedAt))
        }

        let staleIDs = Self.sessionIDsToCloseByPID(sessions: tuples)
        for sessionId in staleIDs {
            try? sessionIndex.updateRuntimeState(sessionId: sessionId, status: "closed", pid: nil)
        }
    }
```

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/Watchers/Indexer.swift Tests/VibeLightTests/PIDDeduplicationTests.swift
git commit -m "fix: deduplicate live sessions sharing the same PID"
```

---

### Task 3: Create Web UI Assets (panel.css)

**Files:**
- Create: `Sources/VibeLight/Resources/Web/panel.css`

- [ ] **Step 1: Create the Web resources directory**

```bash
mkdir -p /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation/Sources/VibeLight/Resources/Web
```

- [ ] **Step 2: Write panel.css with all design tokens and animations**

Create `Sources/VibeLight/Resources/Web/panel.css`:

```css
/* VibeLight Panel — Ethereal Terminal Design System */
/* All tokens from DESIGN.md mapped to CSS custom properties */

:root {
  /* Surfaces — Dark Mode (default) */
  --bg: #08090A;
  --surface: #111314;
  --surface-card: #161819;

  /* Accents */
  --neon: #AAFFDC;
  --neon-dim: #00E1AB;
  --neon-glow: rgba(170,255,220,0.12);
  --neon-glow-strong: rgba(170,255,220,0.25);
  --working-blue: #82AAFF;
  --waiting-amber: #FFC965;
  --amber-glow: rgba(255,201,101,0.15);
  --activity-cyan: #7DD8C0;
  --claude: #D97757;
  --codex: #10A37F;

  /* Labels */
  --label: #DEE4E1;
  --label-secondary: rgba(222,228,225,0.5);
  --label-tertiary: rgba(222,228,225,0.22);

  /* Structural */
  --separator: rgba(255,255,255,0.04);
  --selection: rgba(170,255,220,0.06);
  --selection-edge: rgba(170,255,220,0.08);
  --ghost: rgba(170,255,220,0.04);
  --kicker: #AAFFDC;

  /* Panel */
  --panel-bg: rgba(17,19,20,0.82);
  --panel-shadow: 0 0 120px rgba(170,255,220,0.04), 0 0 40px rgba(170,255,220,0.02), 0 32px 80px rgba(0,0,0,0.5);

  /* Spacing */
  --panel-width: 720px;
  --panel-radius: 12px;
  --row-radius: 6px;
  --row-h-closed: 56px;
  --row-h-active: 74px;
  --row-v-pad: 10px;
  --row-h-pad: 14px;
  --icon-size: 32px;
  --icon-radius: 5px;
  --logo-gap: 12px;
  --search-height: 64px;
  --search-h-pad: 22px;
  --search-top-pad: 14px;
  --results-h-pad: 6px;
  --results-bottom-pad: 12px;

  /* Typography */
  --font-title: 'JetBrains Mono', ui-monospace, monospace;
  --font-ui: -apple-system, 'SF Pro', system-ui, sans-serif;
  --font-activity: 'JetBrains Mono', ui-monospace, monospace;
  --font-status: 'JetBrains Mono', ui-monospace, monospace;
  --font-hint: 'JetBrains Mono', ui-monospace, monospace;
}

/* Light mode overrides */
[data-theme="light"] {
  --bg: #F4F7F6;
  --surface: #E8EDEB;
  --surface-card: #FFFFFF;
  --label: #151917;
  --label-secondary: #3A4A43;
  --label-tertiary: rgba(58,74,67,0.35);
  --separator: rgba(58,74,67,0.06);
  --selection: rgba(0,225,171,0.06);
  --selection-edge: transparent;
  --ghost: rgba(185,203,193,0.12);
  --kicker: #006B54;
  --panel-bg: rgba(244,247,246,0.85);
  --panel-shadow: 0 32px 80px rgba(0,0,0,0.08);
}

/* Reset */
*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  background: transparent;
  overflow: hidden;
  -webkit-user-select: none;
  user-select: none;
  font-family: var(--font-ui);
  color: var(--label);
}

/* Panel */
.panel {
  width: var(--panel-width);
  background: var(--panel-bg);
  -webkit-backdrop-filter: blur(48px) saturate(200%);
  backdrop-filter: blur(48px) saturate(200%);
  border: 1px solid var(--ghost);
  border-radius: var(--panel-radius);
  box-shadow: var(--panel-shadow);
  position: relative;
  overflow: hidden;
}

.panel__top-edge {
  position: absolute;
  top: 0;
  left: 15%;
  right: 15%;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--neon-glow-strong), transparent);
  z-index: 1;
}

[data-theme="light"] .panel__top-edge {
  display: none;
}

.panel__scanlines {
  position: absolute;
  inset: 0;
  background: repeating-linear-gradient(
    0deg,
    transparent,
    transparent 1px,
    rgba(0,0,0,0.008) 1px,
    rgba(0,0,0,0.008) 2px
  );
  pointer-events: none;
  z-index: 2;
}

[data-theme="light"] .panel__scanlines {
  display: none;
}

/* Search bar */
.search-bar {
  display: flex;
  align-items: center;
  height: var(--search-height);
  padding: var(--search-top-pad) var(--search-h-pad) 0;
  gap: 12px;
  position: relative;
  z-index: 3;
}

.search-icon {
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  color: var(--label-secondary);
}

.search-input-wrapper {
  flex: 1;
  position: relative;
  min-width: 0;
}

.search-input {
  width: 100%;
  background: transparent;
  border: none;
  outline: none;
  font-family: var(--font-ui);
  font-size: 24px;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: var(--label);
  caret-color: var(--neon-dim);
}

.search-input::placeholder {
  color: var(--label-tertiary);
}

.ghost-suggestion {
  position: absolute;
  top: 0;
  left: 0;
  font-family: var(--font-ui);
  font-size: 24px;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: var(--label-tertiary);
  pointer-events: none;
  white-space: nowrap;
  overflow: hidden;
}

.action-hint {
  font-family: var(--font-hint);
  font-size: 11px;
  color: var(--label-tertiary);
  white-space: nowrap;
  flex-shrink: 0;
}

.search-bar__tool-icon {
  width: var(--icon-size);
  height: var(--icon-size);
  border-radius: var(--icon-radius);
  flex-shrink: 0;
  object-fit: cover;
}

.search-bar__tool-icon[src=""],
.search-bar__tool-icon:not([src]) {
  display: none;
}

/* Separator */
.separator {
  height: 1px;
  margin: 14px 20px 0;
  background: var(--separator);
  position: relative;
  z-index: 3;
}

/* Results */
.results {
  padding: 8px var(--results-h-pad) var(--results-bottom-pad);
  overflow-y: auto;
  position: relative;
  z-index: 3;
}

.results::-webkit-scrollbar {
  width: 6px;
}

.results::-webkit-scrollbar-track {
  background: transparent;
}

.results::-webkit-scrollbar-thumb {
  background: var(--label-tertiary);
  border-radius: 3px;
}

/* Row */
.row {
  display: flex;
  align-items: flex-start;
  gap: var(--logo-gap);
  padding: var(--row-v-pad) var(--row-h-pad);
  border-radius: var(--row-radius);
  cursor: default;
  border: 1px solid transparent;
  transition: background 150ms ease-out, border-color 150ms ease-out;
}

.row--selected {
  background: var(--selection);
  border-color: var(--selection-edge);
}

/* Row icon */
.row__icon {
  width: var(--icon-size);
  height: var(--icon-size);
  border-radius: var(--icon-radius);
  flex-shrink: 0;
  object-fit: cover;
  margin-top: 2px;
}

.row__icon-fallback {
  width: var(--icon-size);
  height: var(--icon-size);
  border-radius: 3px;
  flex-shrink: 0;
  margin-top: 2px;
  background: #555;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-ui);
  font-size: 15px;
  font-weight: 700;
  color: #fff;
}

/* Row body */
.row__body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.row__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.row__title {
  font-family: var(--font-title);
  font-size: 14px;
  font-weight: 500;
  letter-spacing: -0.01em;
  color: var(--label);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}

.row__status {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.row__status-text {
  font-family: var(--font-status);
  font-size: 10px;
  font-weight: 500;
  letter-spacing: 0.1em;
  text-transform: uppercase;
}

.row__meta {
  font-family: var(--font-ui);
  font-size: 12px;
  color: var(--label-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.row__activity {
  font-family: var(--font-activity);
  font-size: 11.5px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.row__activity--tool,
.row__activity--fileEdit {
  color: var(--activity-cyan);
}

.row__activity--assistant {
  font-family: var(--font-ui);
  font-style: italic;
  color: var(--label-secondary);
  opacity: 0.55;
}

/* Status dot */
.status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}

.status-dot--green {
  background: var(--neon-dim);
  box-shadow: 0 0 4px var(--neon-glow);
  animation: pulse 2s ease-in-out infinite;
}

.status-dot--amber {
  background: var(--waiting-amber);
  box-shadow: 0 0 4px var(--amber-glow);
  animation: pulse 2s ease-in-out infinite;
}

/* Typing dots */
.typing-dots {
  display: flex;
  align-items: center;
  gap: 3px;
}

.typing-dot {
  width: 3.5px;
  height: 3.5px;
  border-radius: 50%;
  background: var(--neon-dim);
  animation: bounce 1.4s infinite;
}

[data-theme="light"] .typing-dot {
  background: var(--label-tertiary);
}

.typing-dot:nth-child(2) { animation-delay: 0.2s; }
.typing-dot:nth-child(3) { animation-delay: 0.4s; }

/* Row states */

/* Working — shimmer title */
.row--working .row__title {
  background: linear-gradient(90deg, var(--label) 0%, var(--neon) 50%, var(--label) 100%);
  background-size: 200%;
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  animation: shimmer 2.5s linear infinite;
}

/* Waiting — breathing status text */
.row--waiting .row__status-text {
  color: var(--waiting-amber);
  animation: breathe 3s ease-in-out infinite alternate;
}

/* Closed — dimmed title */
.row--closed .row__title {
  opacity: 0.35;
}

.row--closed .row__icon {
  opacity: 0.35;
}

/* Action — neon title */
.row--action .row__title {
  color: var(--neon);
  -webkit-text-fill-color: var(--neon);
}

[data-theme="light"] .row--action .row__title {
  color: var(--neon-dim);
  -webkit-text-fill-color: var(--neon-dim);
}

.row--action .row__title {
  text-shadow: 0 0 12px var(--neon-glow);
}

/* Keyframes */
@keyframes shimmer {
  from { background-position: 100% 0; }
  to { background-position: -100% 0; }
}

@keyframes breathe {
  from { opacity: 0.4; }
  to { opacity: 0.9; }
}

@keyframes bounce {
  0%, 60%, 100% { transform: translateY(0); }
  30% { transform: translateY(-3px); }
}

@keyframes pulse {
  0%, 100% { transform: scale(1); opacity: 0.6; }
  50% { transform: scale(1.2); opacity: 1; }
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/Resources/Web/panel.css
git commit -m "feat: add panel CSS with all design tokens and animations"
```

---

### Task 4: Create Web UI Assets (panel.html)

**Files:**
- Create: `Sources/VibeLight/Resources/Web/panel.html`

- [ ] **Step 1: Write panel.html**

Create `Sources/VibeLight/Resources/Web/panel.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="panel.css">
</head>
<body>
  <div class="panel" id="panel">
    <div class="panel__top-edge"></div>
    <div class="panel__scanlines"></div>

    <div class="search-bar">
      <svg class="search-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5">
        <circle cx="8.5" cy="8.5" r="6"/>
        <line x1="13" y1="13" x2="18" y2="18"/>
      </svg>
      <div class="search-input-wrapper">
        <input class="search-input" id="searchInput" type="text" placeholder="Search sessions" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">
        <span class="ghost-suggestion" id="ghostSuggestion"></span>
      </div>
      <span class="action-hint" id="actionHint"></span>
      <img class="search-bar__tool-icon" id="searchBarIcon" src="">
    </div>

    <div class="separator"></div>

    <div class="results" id="results"></div>
  </div>

  <script src="panel.js"></script>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/Resources/Web/panel.html
git commit -m "feat: add panel HTML structure"
```

---

### Task 5: Create Web UI Assets (panel.js)

**Files:**
- Create: `Sources/VibeLight/Resources/Web/panel.js`

- [ ] **Step 1: Write panel.js**

Create `Sources/VibeLight/Resources/Web/panel.js`:

```javascript
// VibeLight Panel — JS Controller
// Handles: search input, keyboard navigation, result rendering, ghost suggestions
// All navigation is DOM-only — no Swift round-trip for arrow keys

(function() {
  'use strict';

  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge;
  const searchInput = document.getElementById('searchInput');
  const ghostSuggestion = document.getElementById('ghostSuggestion');
  const actionHint = document.getElementById('actionHint');
  const searchBarIcon = document.getElementById('searchBarIcon');
  const resultsContainer = document.getElementById('results');
  const panel = document.getElementById('panel');

  let currentResults = [];
  let selectedIndex = 0;
  let debounceTimer = null;
  let iconBaseURL = '';

  // --- Swift → JS API ---

  window.updateResults = function(resultsJSON) {
    const newResults = typeof resultsJSON === 'string' ? JSON.parse(resultsJSON) : resultsJSON;
    currentResults = newResults;
    renderResults();
    if (currentResults.length > 0) {
      selectedIndex = Math.min(selectedIndex, currentResults.length - 1);
    } else {
      selectedIndex = 0;
    }
    updateSelection();
    updateActionHint();
    notifyResize();
  };

  window.setTheme = function(theme) {
    document.documentElement.setAttribute('data-theme', theme);
  };

  window.setGhostSuggestion = function(text) {
    updateGhostDisplay(text);
  };

  window.resetAndFocus = function() {
    searchInput.value = '';
    ghostSuggestion.textContent = '';
    selectedIndex = 0;
    currentResults = [];
    resultsContainer.innerHTML = '';
    searchInput.focus();
    notifyResize();
  };

  window.setIconBaseURL = function(url) {
    iconBaseURL = url;
  };

  // --- Search Input ---

  searchInput.addEventListener('input', function() {
    clearTimeout(debounceTimer);
    updateGhostFromInput();
    debounceTimer = setTimeout(function() {
      if (bridge) {
        bridge.postMessage({ type: 'search', query: searchInput.value });
      }
    }, 80);
  });

  // --- Keyboard Navigation ---

  document.addEventListener('keydown', function(e) {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        moveSelection(1);
        break;
      case 'ArrowUp':
        e.preventDefault();
        moveSelection(-1);
        break;
      case 'Enter':
        e.preventDefault();
        activateSelected();
        break;
      case 'Escape':
        e.preventDefault();
        if (bridge) bridge.postMessage({ type: 'escape' });
        break;
      case 'Tab':
        e.preventDefault();
        if (!acceptGhostSuggestion()) {
          drillIntoSelectedHistory();
        }
        break;
      case 'ArrowRight':
        if (searchInput.selectionStart === searchInput.value.length) {
          acceptGhostSuggestion();
        }
        break;
    }
  });

  function moveSelection(delta) {
    if (currentResults.length === 0) return;
    const prev = selectedIndex;
    selectedIndex = Math.max(0, Math.min(currentResults.length - 1, selectedIndex + delta));
    if (prev !== selectedIndex) {
      updateSelection();
      updateActionHint();
    }
  }

  function updateSelection() {
    const rows = resultsContainer.querySelectorAll('.row');
    rows.forEach(function(row, i) {
      row.classList.toggle('row--selected', i === selectedIndex);
    });
    if (rows[selectedIndex]) {
      rows[selectedIndex].scrollIntoView({ block: 'nearest' });
    }
  }

  function activateSelected() {
    if (currentResults.length === 0) return;
    const result = currentResults[selectedIndex];
    if (result && bridge) {
      bridge.postMessage({ type: 'select', sessionId: result.sessionId, status: result.status, tool: result.tool });
    }
  }

  // --- Ghost Suggestions ---

  function updateGhostFromInput() {
    if (!searchInput.value) {
      ghostSuggestion.textContent = '';
      return;
    }
    // Ghost is updated from Swift via setGhostSuggestion
  }

  function updateGhostDisplay(suggestion) {
    if (!suggestion || !searchInput.value || !suggestion.toLowerCase().startsWith(searchInput.value.toLowerCase())) {
      ghostSuggestion.textContent = '';
      return;
    }
    // Show full suggestion but make typed portion invisible
    const typed = searchInput.value;
    const spacer = typed.replace(/./g, '\u00A0'); // invisible spacer matching typed width
    ghostSuggestion.textContent = spacer + suggestion.slice(typed.length);
  }

  function acceptGhostSuggestion() {
    var fullText = '';
    // Reconstruct full suggestion from ghost display
    if (ghostSuggestion.textContent && ghostSuggestion.textContent.trim()) {
      var suffix = ghostSuggestion.textContent.replace(/^\u00A0+/, '');
      fullText = searchInput.value + suffix;
    }
    if (!fullText || fullText === searchInput.value) return false;
    searchInput.value = fullText;
    ghostSuggestion.textContent = '';
    if (bridge) {
      bridge.postMessage({ type: 'search', query: searchInput.value });
    }
    return true;
  }

  function drillIntoSelectedHistory() {
    if (currentResults.length === 0) return;
    var result = currentResults[selectedIndex];
    if (!result || result.status === 'live' || result.status === 'action' || !result.title) return;
    searchInput.value = result.title;
    ghostSuggestion.textContent = '';
    if (bridge) {
      bridge.postMessage({ type: 'search', query: searchInput.value });
    }
  }

  // --- Action Hint ---

  function updateActionHint() {
    if (currentResults.length === 0) {
      actionHint.textContent = '';
      searchBarIcon.src = '';
      return;
    }
    var result = currentResults[selectedIndex] || currentResults[0];
    var iconSrc = toolIconURL(result.tool);
    searchBarIcon.src = iconSrc || '';

    if (result.status === 'action') {
      actionHint.textContent = '\u21A9 Launch';
    } else if (result.status === 'live') {
      actionHint.textContent = '\u21A9 Switch';
    } else {
      actionHint.textContent = '\u21A9 Resume \u21E5 History';
    }
  }

  // --- Result Rendering ---

  function renderResults() {
    resultsContainer.innerHTML = '';
    currentResults.forEach(function(result, index) {
      resultsContainer.appendChild(createRow(result, index));
    });
  }

  function createRow(result, index) {
    var row = document.createElement('div');
    row.className = 'row';
    row.dataset.index = index;

    // State classes
    if (result.status === 'action') {
      row.classList.add('row--action');
    } else if (result.activityStatus === 'working') {
      row.classList.add('row--working');
    } else if (result.activityStatus === 'waiting') {
      row.classList.add('row--waiting');
    } else if (result.activityStatus === 'closed' || result.status !== 'live') {
      row.classList.add('row--closed');
    }

    if (index === selectedIndex) {
      row.classList.add('row--selected');
    }

    // Icon
    var iconSrc = toolIconURL(result.tool);
    if (iconSrc) {
      var icon = document.createElement('img');
      icon.className = 'row__icon';
      icon.src = iconSrc;
      icon.draggable = false;
      row.appendChild(icon);
    } else {
      var fallback = document.createElement('div');
      fallback.className = 'row__icon-fallback';
      fallback.textContent = (result.tool || '?')[0].toUpperCase();
      row.appendChild(fallback);
    }

    // Body
    var body = document.createElement('div');
    body.className = 'row__body';

    // Header (title + status)
    var header = document.createElement('div');
    header.className = 'row__header';

    var title = document.createElement('span');
    title.className = 'row__title';
    title.textContent = result.title;
    header.appendChild(title);

    var status = createStatusElement(result);
    if (status) header.appendChild(status);

    body.appendChild(header);

    // Metadata
    var meta = document.createElement('span');
    meta.className = 'row__meta';
    meta.textContent = formatMetadata(result);
    body.appendChild(meta);

    // Activity
    if (result.activityPreview && result.activityStatus !== 'closed') {
      var activity = document.createElement('span');
      activity.className = 'row__activity';
      var kind = result.activityPreviewKind || 'tool';
      if (kind === 'assistant') {
        activity.classList.add('row__activity--assistant');
      } else {
        activity.classList.add('row__activity--tool');
      }
      activity.textContent = result.activityPreview;
      body.appendChild(activity);
    }

    row.appendChild(body);

    // Click handler
    row.addEventListener('click', function() {
      selectedIndex = index;
      updateSelection();
      updateActionHint();
    });

    row.addEventListener('dblclick', function() {
      selectedIndex = index;
      activateSelected();
    });

    return row;
  }

  function createStatusElement(result) {
    if (result.activityStatus === 'working') {
      var status = document.createElement('div');
      status.className = 'row__status';

      var dot = document.createElement('span');
      dot.className = 'status-dot status-dot--green';
      status.appendChild(dot);

      var dots = document.createElement('div');
      dots.className = 'typing-dots';
      for (var i = 0; i < 3; i++) {
        var d = document.createElement('span');
        d.className = 'typing-dot';
        dots.appendChild(d);
      }
      status.appendChild(dots);
      return status;
    }

    if (result.activityStatus === 'waiting') {
      var status = document.createElement('div');
      status.className = 'row__status';

      var dot = document.createElement('span');
      dot.className = 'status-dot status-dot--amber';
      status.appendChild(dot);

      var text = document.createElement('span');
      text.className = 'row__status-text';
      text.textContent = 'AWAITING';
      status.appendChild(text);
      return status;
    }

    return null;
  }

  function formatMetadata(result) {
    var parts = [];
    if (result.relativeTime) parts.push(result.relativeTime);
    var projectName = result.projectName || lastPathComponent(result.project);
    if (projectName) {
      var branch = (result.gitBranch || '').trim();
      parts.push(branch ? projectName + ' / ' + branch : projectName);
    }
    if (result.tokenCount > 0) {
      parts.push(formatTokens(result.tokenCount));
    }
    return parts.join(' \u00B7 ');
  }

  function formatTokens(count) {
    if (count >= 1000) {
      return (count / 1000).toFixed(1) + 'k tokens';
    }
    return count + ' tokens';
  }

  function lastPathComponent(path) {
    if (!path) return '';
    var parts = path.split('/');
    return parts[parts.length - 1] || '';
  }

  function toolIconURL(tool) {
    if (!tool) return null;
    var name = tool.toLowerCase();
    var assetMap = { claude: 'claude-icon', codex: 'codex-icon', gemini: 'gemini-icon' };
    var asset = assetMap[name];
    if (!asset) return null;
    if (iconBaseURL) return iconBaseURL + '/' + asset + '.png';
    return asset + '.png';
  }

  // --- Resize Notification ---

  function notifyResize() {
    requestAnimationFrame(function() {
      var height = panel.offsetHeight;
      if (bridge) {
        bridge.postMessage({ type: 'resize', height: height });
      }
    });
  }

  // --- Init ---
  searchInput.focus();
})();
```

- [ ] **Step 2: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/Resources/Web/panel.js
git commit -m "feat: add panel JS with search, navigation, and rendering"
```

---

### Task 6: Create WebBridge (Swift↔JS Communication)

**Files:**
- Create: `Sources/VibeLight/UI/WebBridge.swift`
- Create: `Tests/VibeLightTests/WebBridgeTests.swift`

- [ ] **Step 1: Write failing test for WebBridge message parsing**

```swift
// Tests/VibeLightTests/WebBridgeTests.swift
import Testing
import Foundation
@testable import VibeLight

@Suite("WebBridge message parsing")
struct WebBridgeTests {
    @Test("parses search message")
    func parseSearchMessage() {
        let body: [String: Any] = ["type": "search", "query": "hello"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .search(query: "hello"))
    }

    @Test("parses select message")
    func parseSelectMessage() {
        let body: [String: Any] = ["type": "select", "sessionId": "abc-123", "status": "live", "tool": "claude"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .select(sessionId: "abc-123", status: "live", tool: "claude"))
    }

    @Test("parses escape message")
    func parseEscapeMessage() {
        let body: [String: Any] = ["type": "escape"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .escape)
    }

    @Test("parses resize message")
    func parseResizeMessage() {
        let body: [String: Any] = ["type": "resize", "height": 400.0]
        let message = WebBridge.Message.parse(body)
        #expect(message == .resize(height: 400.0))
    }

    @Test("returns nil for unknown message type")
    func unknownMessage() {
        let body: [String: Any] = ["type": "unknown"]
        let message = WebBridge.Message.parse(body)
        #expect(message == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter WebBridgeTests 2>&1 | head -20`
Expected: Compilation error — `WebBridge` does not exist.

- [ ] **Step 3: Write WebBridge.swift**

```swift
// Sources/VibeLight/UI/WebBridge.swift
import Foundation
import WebKit

@MainActor
protocol WebBridgeDelegate: AnyObject {
    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String)
    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String)
    func webBridgeDidRequestEscape(_ bridge: WebBridge)
    func webBridge(_ bridge: WebBridge, didRequestResize height: CGFloat)
}

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    enum Message: Equatable {
        case search(query: String)
        case select(sessionId: String, status: String, tool: String)
        case escape
        case resize(height: CGFloat)

        static func parse(_ body: [String: Any]) -> Message? {
            guard let type = body["type"] as? String else { return nil }
            switch type {
            case "search":
                let query = body["query"] as? String ?? ""
                return .search(query: query)
            case "select":
                let sessionId = body["sessionId"] as? String ?? ""
                let status = body["status"] as? String ?? ""
                let tool = body["tool"] as? String ?? ""
                return .select(sessionId: sessionId, status: status, tool: tool)
            case "escape":
                return .escape
            case "resize":
                let height = body["height"] as? Double ?? 0
                return .resize(height: CGFloat(height))
            default:
                return nil
            }
        }
    }

    weak var delegate: WebBridgeDelegate?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        guard let parsed = Message.parse(body) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch parsed {
            case .search(let query):
                delegate?.webBridge(self, didReceiveSearch: query)
            case .select(let sessionId, let status, let tool):
                delegate?.webBridge(self, didSelectSession: sessionId, status: status, tool: tool)
            case .escape:
                delegate?.webBridgeDidRequestEscape(self)
            case .resize(let height):
                delegate?.webBridge(self, didRequestResize: height)
            }
        }
    }

    static func resultToJSON(_ result: SearchResult) -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": result.sessionId,
            "tool": result.tool,
            "title": result.title,
            "project": result.project,
            "projectName": result.projectName,
            "gitBranch": result.gitBranch,
            "status": result.status,
            "tokenCount": result.tokenCount,
            "activityStatus": result.activityStatus.rawValue,
            "relativeTime": RelativeTimeFormatter.string(from: result.lastActivityAt),
        ]
        if let preview = result.activityPreview {
            dict["activityPreview"] = preview.text
            dict["activityPreviewKind"] = preview.kind.rawValue
        }
        return dict
    }

    static func resultsToJSONString(_ results: [SearchResult]) -> String {
        let array = results.map { resultToJSON($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test --filter WebBridgeTests 2>&1 | tail -10`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/UI/WebBridge.swift Tests/VibeLightTests/WebBridgeTests.swift
git commit -m "feat: add WebBridge for Swift-JS communication"
```

---

### Task 7: Replace SearchPanelController with WKWebView

**Files:**
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Add WebKit framework to Package.swift**

In `Package.swift`, the WebKit framework is a system framework on macOS — no package dependency needed. But we need to ensure the linker settings don't block it. No changes needed to Package.swift since WebKit is available by default on macOS 14+.

Verify by checking the import compiles:

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift build 2>&1 | tail -5
```

- [ ] **Step 2: Rewrite SearchPanelController.swift**

Replace the entire content of `Sources/VibeLight/UI/SearchPanelController.swift` with:

```swift
import AppKit
import WebKit

@MainActor
final class SearchPanelController: NSObject, WebBridgeDelegate {
    var onSelect: ((SearchResult) -> Void)?
    var sessionIndex: SessionIndex?
    var isVisible: Bool { panel.isVisible }
    var hidesOnDeactivate: Bool { panel.hidesOnDeactivate }

    private let panel: SearchPanel
    private let webView: WKWebView
    private let webBridge = WebBridge()
    private let searchDebouncer = Debouncer(delay: 0.08)

    private var results: [SearchResult] = []
    private var deactivationObserver: NSObjectProtocol?
    private var panelResignKeyObserver: NSObjectProtocol?
    private var lastPushedResultsJSON: String = ""

    private let panelWidth: CGFloat = 720
    private let minPanelHeight: CGFloat = 104

    private static let isRunningTests: Bool = {
        if NSClassFromString("XCTestCase") != nil { return true }
        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") { return true }
        return ProcessInfo.processInfo.environment.keys.contains { key in
            key.localizedCaseInsensitiveContains("xctest")
                || key.localizedCaseInsensitiveContains("swift_testing")
        }
    }()

    override init() {
        self.panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: minPanelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        contentController.add(webBridge, name: "bridge")
        webBridge.delegate = self

        configurePanel()
        configureWebView()
        configureInteractions()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        searchDebouncer.cancel()

        if !panel.isVisible {
            centerPanelOnActiveScreen()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        webView.evaluateJavaScript("resetAndFocus()", completionHandler: nil)
        pushTheme()
        refreshResults(query: "")
    }

    func hide() {
        searchDebouncer.cancel()
        panel.orderOut(nil)
    }

    // MARK: - WebBridgeDelegate

    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String) {
        refreshResults(query: query)
    }

    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String) {
        guard let result = results.first(where: { $0.sessionId == sessionId }) else { return }
        hide()
        onSelect?(result)
    }

    func webBridgeDidRequestEscape(_ bridge: WebBridge) {
        hide()
    }

    func webBridge(_ bridge: WebBridge, didRequestResize height: CGFloat) {
        guard height > 0 else { return }
        var frame = panel.frame
        let maxY = frame.maxY
        let newHeight = max(minPanelHeight, height + 2) // +2 for border
        frame.size = NSSize(width: panelWidth, height: newHeight)
        frame.origin.y = maxY - newHeight
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    // MARK: - Private

    private func refreshResults(query: String) {
        guard let sessionIndex else {
            pushResults([])
            return
        }

        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = try sessionIndex.search(query: trimmed, liveOnly: trimmed.isEmpty)
            if trimmed.lowercased().hasPrefix("new") {
                let actionRows = makeNewSessionActionRows()
                pushResults(actionRows + matches)
            } else {
                pushResults(matches)
            }
        } catch {
            pushResults([])
            print("SearchPanelController search failed: \(error)")
        }
    }

    private func pushResults(_ newResults: [SearchResult]) {
        results = newResults
        let json = WebBridge.resultsToJSONString(results)

        // Skip push if results haven't changed
        guard json != lastPushedResultsJSON else { return }
        lastPushedResultsJSON = json

        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView.evaluateJavaScript("updateResults('\(escaped)')", completionHandler: nil)

        updateGhostSuggestion()
    }

    private func updateGhostSuggestion() {
        // Get the current search query from JS and compute ghost
        webView.evaluateJavaScript("document.getElementById('searchInput').value") { [weak self] value, _ in
            guard let self, let query = value as? String, !query.isEmpty else {
                self?.webView.evaluateJavaScript("setGhostSuggestion(null)", completionHandler: nil)
                return
            }

            let suggestion = self.computeGhostSuggestion(query: query)
            if let suggestion {
                let escaped = suggestion.replacingOccurrences(of: "'", with: "\\'")
                self.webView.evaluateJavaScript("setGhostSuggestion('\(escaped)')", completionHandler: nil)
            } else {
                self.webView.evaluateJavaScript("setGhostSuggestion(null)", completionHandler: nil)
            }
        }
    }

    private func computeGhostSuggestion(query: String) -> String? {
        let titleMatch = results.first(where: {
            $0.title.lowercased().hasPrefix(query.lowercased())
        })?.title

        let projectMatch = titleMatch ?? results.first(where: {
            let name = $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
            return name.lowercased().hasPrefix(query.lowercased())
        }).map {
            $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
        }

        return titleMatch ?? projectMatch
    }

    private func makeNewSessionActionRows() -> [SearchResult] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let recentProject = (try? sessionIndex?.mostRecentProject()) ?? nil
        let project = recentProject?.project.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = recentProject?.projectName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedProject = project.isEmpty ? homePath : project
        let resolvedProjectName = projectName.isEmpty ? "~" : projectName
        let now = Date()

        return [
            SearchResult(
                sessionId: "new-claude", tool: "claude", title: "New Claude session",
                project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
                status: "action", startedAt: now, pid: nil, tokenCount: 0,
                lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
            ),
            SearchResult(
                sessionId: "new-codex", tool: "codex", title: "New Codex session",
                project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
                status: "action", startedAt: now, pid: nil, tokenCount: 0,
                lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
            ),
        ]
    }

    private func pushTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? "dark" : "light"
        webView.evaluateJavaScript("setTheme('\(theme)')", completionHandler: nil)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // Shadow handled by CSS
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
    }

    private func configureWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")

        panel.contentView = webView

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            webView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            webView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
        ])

        // Load panel.html from bundle
        if let htmlURL = Bundle.module.url(forResource: "panel", withExtension: "html", subdirectory: "Web") {
            // Set icon base URL for JS
            let iconDir = Bundle.module.url(forResource: "claude-icon", withExtension: "png")?.deletingLastPathComponent()
            if let iconDir {
                webView.evaluateJavaScript("setIconBaseURL('\(iconDir.absoluteString)')", completionHandler: nil)
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    private func configureInteractions() {
        guard !Self.isRunningTests else { return }

        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }

        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard NSApp.isActive else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard panel.isVisible, !panel.isKeyWindow, NSApp.isActive else { return }
                guard let keyWindow = NSApp.keyWindow, keyWindow !== panel else { return }
                hide()
            }
        }

        // Watch for appearance changes to push theme
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pushTheme() }
        }
    }

    @MainActor
    deinit {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func centerPanelOnActiveScreen() {
        guard let screen = activeScreen() else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let topOffset = max(visibleFrame.height * 0.18, 96)
        let origin = NSPoint(
            x: visibleFrame.midX - panelWidth / 2,
            y: max(visibleFrame.minY + 24, visibleFrame.maxY - panel.frame.height - topOffset)
        )
        panel.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift build 2>&1 | tail -20`
Expected: Build succeeds. There may be warnings about unused files that we'll delete in the next task.

- [ ] **Step 4: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add Sources/VibeLight/UI/SearchPanelController.swift
git commit -m "feat: replace AppKit views with WKWebView panel"
```

---

### Task 8: Delete Replaced AppKit UI Files

**Files:**
- Delete: `Sources/VibeLight/UI/ResultRowView.swift`
- Delete: `Sources/VibeLight/UI/ResultsTableView.swift`
- Delete: `Sources/VibeLight/UI/DesignTokens.swift`
- Delete: `Sources/VibeLight/UI/SearchField.swift`
- Delete: `Sources/VibeLight/UI/ToolIcon.swift`

- [ ] **Step 1: Check which files still reference deleted types**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && grep -rn "DesignTokens\|ResultRowView\|ResultsTableView\|SearchField\|ToolIcon" Sources/ --include="*.swift" | grep -v ".build/" | grep -v "ResultRowView.swift\|ResultsTableView.swift\|DesignTokens.swift\|SearchField.swift\|ToolIcon.swift"`

Expected: Only references should be in `SearchPanelController.swift` (which was already rewritten to not use them). If any other files reference these types, update them first.

- [ ] **Step 2: Delete the files**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
rm Sources/VibeLight/UI/ResultRowView.swift
rm Sources/VibeLight/UI/ResultsTableView.swift
rm Sources/VibeLight/UI/DesignTokens.swift
rm Sources/VibeLight/UI/SearchField.swift
rm Sources/VibeLight/UI/ToolIcon.swift
```

- [ ] **Step 3: Fix any remaining compilation errors**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift build 2>&1 | tail -30`

If `DesignTokens` is referenced in test files, update them. The `ToolIcon.resourceURL` method was used in `ToolIconTests.swift` — that test file should be removed or updated since ToolIcon no longer exists.

Check: `grep -rn "DesignTokens\|ToolIcon\|SearchField\|ResultRowView\|ResultsTableView" Tests/ --include="*.swift"`

Remove or update test files that reference deleted types:
```bash
rm Tests/VibeLightTests/ToolIconTests.swift
rm Tests/VibeLightTests/DesignTokenTests.swift
rm Tests/VibeLightTests/SearchFieldFocusTests.swift
rm Tests/VibeLightTests/SearchPresentationTests.swift
rm Tests/VibeLightTests/InteractionPolishTests.swift
```

- [ ] **Step 4: Build and run full test suite**

Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift build 2>&1 | tail -10`
Run: `cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation && swift test 2>&1 | tail -20`
Expected: Build succeeds, all remaining tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add -A
git commit -m "refactor: remove replaced AppKit UI files and associated tests"
```

---

### Task 9: Integration Testing and Polish

**Files:**
- Possibly modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Possibly modify: `Sources/VibeLight/Resources/Web/panel.js`
- Possibly modify: `Sources/VibeLight/Resources/Web/panel.css`

- [ ] **Step 1: Build release binary and run**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
swift build -c release 2>&1 | tail -10
```

- [ ] **Step 2: Launch the app and test manually**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
.build/release/VibeLight &
```

Test checklist:
- Press hotkey (Cmd+Shift+L or whatever is configured) — panel should appear
- Type in search field — results should filter with 80ms debounce
- Arrow up/down — selection should move instantly (no lag)
- Press Enter — should switch to/resume the selected session
- Press Escape — panel should dismiss
- Tab — should accept ghost suggestion or drill into history
- Verify tool icons (Claude/Codex) show at 32px
- Verify dark mode: neon accents, ghost borders, CRT scanlines, shimmer on working sessions
- Switch to light mode via right-click menu — verify theme changes
- Verify no duplicate sessions for Codex when using `new`
- Verify console is free of CodexStateDB error spam

- [ ] **Step 3: Fix any issues found during testing**

Address visual alignment issues, icon loading paths, or any JS errors visible in the WebView inspector.

- [ ] **Step 4: Run full test suite one final time**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
swift test 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 5: Final commit**

```bash
cd /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
git add -A
git commit -m "polish: integration testing fixes for WKWebView panel"
```
