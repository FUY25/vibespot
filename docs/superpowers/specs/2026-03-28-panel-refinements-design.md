# Panel Refinements: Error Signals, Smarter Titles, Activity Visibility

**Date:** 2026-03-28
**Branch:** `feat/v1-implementation`
**Status:** Design approved, pending implementation

## Problem

The VibeLight search panel shows sessions but misses important signals:
1. Sessions with API errors, crashes, or stale states look identical to healthy ones
2. Titles are often raw first prompts with ANSI escape codes or unhelpful text
3. The activity preview line is too dim to scan quickly
4. Live sessions show "3h ago" relative time instead of running duration

## Design

### 1. Error/Health Signal System

Add health detection to the indexing pipeline and surface errors as a subtle row tint.

#### Data Model

Add two columns to the `sessions` table:

```sql
healthStatus TEXT DEFAULT 'ok'   -- 'ok' | 'error' | 'stale'
healthDetail TEXT DEFAULT ''     -- short description (e.g. "API 400: model unavailable")
```

#### Detection Rules

Detection runs during `refreshLiveSessions()` in the Indexer (every 3s) and during transcript parsing.

| Signal | Detection | healthStatus |
|--------|-----------|--------------|
| API error | Scan last 20 lines of JSONL for `API Error: \d{3}`, `"type":"invalid_request_error"`, `"type":"authentication_error"`, `overloaded`, `rate_limit` | `error` |
| Crash/exit | PID was live but `kill(pid, 0)` fails and pid file still exists (process didn't clean up) | `error` |
| Stale session | `activityStatus == .working` but `lastActivityAt` > 5 minutes ago with no file modification | `stale` |
| Rate limit / billing | `429` status code or billing-related error messages | `error` |

Health status resets to `ok` when:
- A new successful assistant response appears after an error
- A stale session shows new file activity

#### Visual Treatment

New CSS tokens:

```css
/* Dark mode */
--error-red: #FF6B6B;
--error-tint: rgba(255,107,107,0.06);
--stale-tint: rgba(255,201,101,0.06);

/* Light mode */
--error-red: #E54545;
--error-tint: rgba(229,69,69,0.04);
--stale-tint: rgba(255,201,101,0.04);
```

Row classes:
- `.row--error`: `background: var(--error-tint)` — subtle red wash
- `.row--stale`: `background: var(--stale-tint)` — subtle amber wash

No new UI elements. The row tint IS the signal.

#### Data Flow

1. Indexer detects error condition during refresh or parse
2. Writes `healthStatus` + `healthDetail` to SQLite via `SessionIndex.updateHealthStatus()`
3. `SearchResult` gets new fields: `healthStatus: String`, `healthDetail: String`
4. `WebBridge.resultsToJSONString()` includes `healthStatus` in JSON
5. `panel.js` `createRow()` / `updateRowContent()` applies `.row--error` or `.row--stale` class

### 2. Smarter Titles

Improve title quality by using AI-generated summaries when available and cleaning raw prompts.

#### Title Resolution

| Tool | Live session | Historical session |
|------|-------------|-------------------|
| Claude | Cleaned `firstPrompt` | `summary` > cleaned `firstPrompt` > "Untitled" |
| Codex | `thread_name` (already clean) | `thread_name` > "Untitled" |

#### ANSI Stripping (Swift-side)

Add `stripANSI()` to the indexer so titles are cleaned before storing in SQLite:

```swift
private func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\\x1b\\[[0-9;]*[A-Za-z]",
        with: "",
        options: .regularExpression
    )
}
```

Applied during `upsertSession()` to the title field. JS-side `stripANSI()` remains as a safety net.

#### Smart Truncation

Truncate titles at ~60 characters on word boundaries:

```swift
private func smartTruncate(_ text: String, maxLength: Int = 60) -> String {
    guard text.count > maxLength else { return text }
    let truncated = String(text.prefix(maxLength))
    if let lastSpace = truncated.lastIndex(of: " ") {
        return String(truncated[..<lastSpace]) + "…"
    }
    return truncated + "…"
}
```

Preserve trailing `?` for questions.

### 3. Activity Line Visibility

Make the activity preview line more readable without making it visually dominant.

#### CSS Changes

```css
.row__activity {
  font-size: 12px;           /* was 11.5px — match metadata line */
}

.row__activity--assistant {
  font-style: normal;         /* was italic — hard to read at small mono sizes */
  opacity: 0.7;               /* was 0.55 */
}
```

#### Tool Call Prefix

Add terminal-style `> ` prefix to tool call activity previews in JS:

```js
// In createRow() and updateRowContent()
if (kind === 'tool' || kind === 'fileEdit') {
    activity.textContent = '> ' + stripMarkdown(result.activityPreview);
}
```

### 4. Running Time for Live Sessions

Show elapsed duration instead of relative time for live sessions.

#### JS Implementation

New helper in `panel.js`:

```js
function formatRunningTime(startedAtISO) {
    var start = new Date(startedAtISO);
    var now = new Date();
    var minutes = Math.floor((now - start) / 60000);
    if (minutes < 60) return 'running ' + minutes + 'm';
    var hours = Math.floor(minutes / 60);
    var mins = minutes % 60;
    if (hours >= 3) return 'running ' + hours + 'h+';
    return 'running ' + hours + 'h ' + mins + 'm';
}
```

#### Metadata Line Changes

In `formatMetadata()`:

```js
function formatMetadata(result) {
    var parts = [];
    if (result.status === 'live' && result.startedAt) {
        parts.push(formatRunningTime(result.startedAt));
    } else if (result.relativeTime) {
        parts.push(result.relativeTime);
    }
    // ... rest unchanged
}
```

#### Data Requirement

`startedAt` must be included in the JSON pushed to the web view. Currently `SearchResult` has `startedAt: Date` — add it to `WebBridge.resultsToJSONString()` as an ISO 8601 string.

## Files Affected

| File | Change |
|------|--------|
| `SessionIndex.swift` | Add `healthStatus`/`healthDetail` columns, `updateHealthStatus()`, include `startedAt` in search results |
| `Indexer.swift` | Error detection during `refreshLiveSessions()` and transcript parse |
| `ClaudeParser.swift` | ANSI stripping on title during parse |
| `SearchResult` (in SessionIndex.swift) | Add `healthStatus`, `healthDetail` fields |
| `WebBridge.swift` | Include `healthStatus`, `startedAt` in JSON serialization |
| `panel.css` | Error/stale tint tokens, activity line size/opacity tweaks |
| `panel.js` | Row tint classes, `formatRunningTime()`, `> ` prefix on tool calls, updated `formatMetadata()` |

## Out of Scope

- Error detail view (clicking into a session to see the full error) — future work
- Notifications/alerts for errors — this is visual-only in the panel
- Title generation from transcript heuristics — rely on existing summary/thread_name fields
- Changes to row height or layout density
