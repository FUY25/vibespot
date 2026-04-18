# Search UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 bugs and implement 3 UX improvements to the Flare search panel: correct result ordering, smarter preview card, transcript-matched title display, stable live-session rows, last-user-prompt as running-session title, and terminal cursor focus on jump.

**Architecture:** Changes span the Swift data layer (SessionIndex SQL ordering, new `last_user_prompt` DB column, SearchResult/WebBridge serialization) and the JS UI layer (panel.js rendering logic). Each task is independently testable. No new files needed — all changes are to existing files.

**Tech Stack:** Swift 5.9, SQLite3 (via Database.swift), WKWebView + vanilla JS (panel.js), Swift Testing framework (`@Test`), `swift test` to run tests.

---

## File Map

| File | What changes |
|------|-------------|
| `Sources/VibeLight/Data/SessionIndex.swift` | 1) Add `last_user_prompt` column migration. 2) Fix all `ORDER BY` clauses to use `COALESCE(last_activity_at, started_at) DESC`. 3) Add `last_user_prompt` to SELECT and `mapRow`. 4) Add `updateLastUserPrompt()` method. |
| `Sources/VibeLight/Parsers/Models.swift` | Check if `SearchResult` needs to grow — it doesn't. `lastUserPrompt` goes into `SearchResult` as an optional String. Actually `SearchResult` is defined in `SessionIndex.swift` (line 4). |
| `Sources/VibeLight/UI/WebBridge.swift` | Add `snippet` and `lastUserPrompt` to `resultToJSON`. |
| `Sources/VibeLight/Resources/Web/panel.js` | 1) Use `snippet` (stripped of `>>><<<`) as row title when present. 2) For `activityStatus === 'working'` with no snippet, use `lastUserPrompt` as title. 3) Show last **3** exchanges (not 2) in preview. 4) Remove `state`/`detail` smart-section from preview. 5) Prevent row blink: only rebuild DOM when keys or displayed-title changes. |
| `Sources/VibeLight/Window/WindowJumper.swift` | After activating the terminal app, send a synthesized mouse click or use `activateIgnoringOtherApps` so the cursor lands in the terminal input. |
| `Sources/VibeLight/Watchers/Indexer.swift` | After computing `betterTitle` in `updateLiveSessionTitle`, also save it to `last_user_prompt`. |
| `Tests/VibeLightTests/SessionIndexTests.swift` | Add tests for ordering by `last_activity_at`, and `last_user_prompt` round-trip. |

---

### Task 1: Fix search result ordering (Bug 1)

All three SQL paths in `SessionIndex.search` and `listSessions` order by `started_at`. They should order by `COALESCE(last_activity_at, started_at)` so the most recently active session appears first.

**Files:**
- Modify: `Sources/VibeLight/Data/SessionIndex.swift` (lines ~408, ~450–455, ~488–495, ~560, ~878)
- Test: `Tests/VibeLightTests/SessionIndexTests.swift`

- [ ] **Step 1: Write a failing test**

Add at the bottom of `Tests/VibeLightTests/SessionIndexTests.swift`:

```swift
@Test
func testSearchOrdersByLastActivityAtDescendingNotStartedAt() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()

    // Session A: started first but had recent activity
    try index.upsertSession(
        id: "session-a",
        tool: "claude",
        title: "old session recent activity",
        project: "/p", projectName: "proj", gitBranch: "main",
        status: "closed",
        startedAt: now.addingTimeInterval(-3600), // started 1h ago
        pid: nil,
        lastActivityAt: now.addingTimeInterval(-60) // active 1 min ago
    )

    // Session B: started more recently but has been idle longer
    try index.upsertSession(
        id: "session-b",
        tool: "claude",
        title: "newer session older activity",
        project: "/p", projectName: "proj", gitBranch: "main",
        status: "closed",
        startedAt: now.addingTimeInterval(-1800), // started 30min ago
        pid: nil,
        lastActivityAt: now.addingTimeInterval(-3600) // active 1h ago
    )

    let results = try index.search(query: "", includeHistory: true)
    let ids = results.map(\.sessionId)
    // session-a should be first because its lastActivityAt is more recent
    #expect(ids.first == "session-a", "Most recently active session should rank first")
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
cd /Users/fuyuming/Desktop/project/vibelight
swift test --filter testSearchOrdersByLastActivityAtDescendingNotStartedAt 2>&1 | tail -20
```

Expected: FAIL — `session-b` appears first because of `started_at` ordering.

- [ ] **Step 3: Fix all ORDER BY clauses in SessionIndex.swift**

In `Sources/VibeLight/Data/SessionIndex.swift`, make these replacements:

**In `listSessions` (line ~878):**
```swift
// OLD:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
// NEW:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, COALESCE(last_activity_at, started_at) DESC
```

**In `metadataSQL` inside `search` (line ~408):**
```swift
// OLD:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
// NEW:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, COALESCE(last_activity_at, started_at) DESC
```

**In `transcriptSQL` `deduplicated_matches` CTE ORDER BY (line ~450):**
```sql
-- OLD:
ORDER BY
    status_priority,
    match_rank,
    session_started_at DESC,
-- NEW:
ORDER BY
    status_priority,
    match_rank,
    COALESCE(s.last_activity_at, s.started_at) DESC,
```
Note: `deduplicated_matches` doesn't have `s.*` in scope; the `session_started_at` column comes from `ranked_matches`. We need to propagate `last_activity_at` through all CTEs. Change `ranked_matches` to also select the coalesced column, and thread it through `session_matches`:

```sql
-- In ranked_matches CTE, add alongside the existing columns:
COALESCE(s.last_activity_at, s.started_at) AS session_last_active,
-- In session_matches CTE, add to the SELECT list:
session_last_active,
-- Then in deduplicated_matches ORDER BY:
ORDER BY
    status_priority,
    match_rank,
    session_last_active DESC,
    transcript_timestamp DESC,
    transcript_rowid DESC
-- And in the final outer ORDER BY:
ORDER BY
    deduplicated_matches.status_priority,
    deduplicated_matches.match_rank,
    deduplicated_matches.session_last_active DESC,
    deduplicated_matches.transcript_timestamp DESC,
    deduplicated_matches.transcript_rowid DESC
```

**In `literalTranscriptSQL` ORDER BY (line ~560):**
```sql
-- OLD:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
-- NEW:
ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, COALESCE(last_activity_at, started_at) DESC
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
swift test --filter testSearchOrdersByLastActivityAtDescendingNotStartedAt 2>&1 | tail -10
```

Expected: PASS

- [ ] **Step 5: Run all SessionIndex tests to catch regressions**

```bash
swift test --filter SessionIndex 2>&1 | tail -20
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Data/SessionIndex.swift Tests/VibeLightTests/SessionIndexTests.swift
git commit -m "fix: order search results by last activity time not started time"
```

---

### Task 2: Add `last_user_prompt` column to DB and SearchResult

We need to store and surface the last user prompt for working sessions. This task adds the DB column, migrates it, and adds it to `SearchResult` + `WebBridge`.

**Files:**
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Sources/VibeLight/UI/WebBridge.swift`

- [ ] **Step 1: Add column migration in SessionIndex.swift**

Find the `ensureSessionColumnExists` block (line ~117–132) and add at the end:

```swift
try ensureSessionColumnExists(name: "last_user_prompt", definition: "TEXT")
```

- [ ] **Step 2: Add `lastUserPrompt` to `SearchResult` struct**

In `SessionIndex.swift`, `SearchResult` struct (line ~4), add the field:

```swift
let lastUserPrompt: String?
```

Add it to the `init` parameter list with default `nil`:

```swift
lastUserPrompt: String? = nil,
```

Add the assignment in `init` body:

```swift
self.lastUserPrompt = lastUserPrompt
```

- [ ] **Step 3: Add `last_user_prompt` to all SELECT queries**

In each SQL SELECT in `SessionIndex.swift` that selects session columns, add `last_user_prompt` after `last_context_sample_at`. There are 4 SQL strings: `listSessions`, `metadataSQL`, `transcriptSQL` outer SELECT, `literalTranscriptSQL` outer SELECT.

For each, append to the SELECT list:
```sql
s.last_user_prompt   -- for queries with JOIN (transcript searches)
last_user_prompt     -- for direct sessions table queries
```

The column index in `mapRow` is currently index 24 (0-based) for `last_context_sample_at`. Add index 25 for `last_user_prompt`.

- [ ] **Step 4: Read `last_user_prompt` in `mapRow`**

Find `mapRow` function in `SessionIndex.swift` (line ~986). After reading `lastContextSampleAt`, add:

```swift
let lastUserPrompt = optionalTextColumn(statement, index: 25)
```

Then add it to the `SearchResult(...)` constructor call:

```swift
lastUserPrompt: lastUserPrompt,
```

- [ ] **Step 5: Add `updateLastUserPrompt` method**

Add a new method to `SessionIndex`:

```swift
func updateLastUserPrompt(sessionId: String, prompt: String) throws {
    try runStatement(
        "UPDATE sessions SET last_user_prompt = ?1 WHERE id = ?2"
    ) { statement in
        try statement.bind(index: 1, text: prompt)
        try statement.bind(index: 2, text: sessionId)
    }
}
```

- [ ] **Step 6: Expose `lastUserPrompt` in WebBridge**

In `Sources/VibeLight/UI/WebBridge.swift`, in `resultToJSON`, add:

```swift
if let lastUserPrompt = result.lastUserPrompt {
    dict["lastUserPrompt"] = lastUserPrompt
}
```

Also add `snippet` (which already exists in `SearchResult` but was never serialized):

```swift
if let snippet = result.snippet {
    dict["snippet"] = snippet
}
```

- [ ] **Step 7: Build to verify no compile errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 8: Commit**

```bash
git add Sources/VibeLight/Data/SessionIndex.swift Sources/VibeLight/UI/WebBridge.swift
git commit -m "feat: add last_user_prompt column and surface snippet+lastUserPrompt to JS"
```

---

### Task 3: Populate `last_user_prompt` in Indexer for live sessions

`updateLiveSessionTitle` in `Indexer.swift` already reads `extractLastUserPrompt`. We just also save it to the new column.

**Files:**
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`

- [ ] **Step 1: Save last user prompt when updating live session title**

In `Indexer.swift`, find `updateLiveSessionTitle` (~line 739). After the `if let betterTitle` block that calls `updateTitle`, also call `updateLastUserPrompt`:

```swift
// Find this existing block:
if result.tool == "codex" {
    betterTitle = codexTitleMap[result.sessionId]
}

// Fall back to last user prompt from JSONL tail
if betterTitle == nil, let fileURL = findSessionFile(sessionId: result.sessionId) {
    betterTitle = TranscriptTailReader.extractLastUserPrompt(fileURL: fileURL)
}

if let betterTitle, !betterTitle.isEmpty {
    try? sessionIndex.updateTitle(sessionId: result.sessionId, title: betterTitle)
}
```

Change to:

```swift
if result.tool == "codex" {
    betterTitle = codexTitleMap[result.sessionId]
}

var lastUserPrompt: String?
if let fileURL = findSessionFile(sessionId: result.sessionId) {
    lastUserPrompt = TranscriptTailReader.extractLastUserPrompt(fileURL: fileURL)
}

if betterTitle == nil {
    betterTitle = lastUserPrompt
}

if let betterTitle, !betterTitle.isEmpty {
    try? sessionIndex.updateTitle(sessionId: result.sessionId, title: betterTitle)
}
if let lastUserPrompt, !lastUserPrompt.isEmpty {
    try? sessionIndex.updateLastUserPrompt(sessionId: result.sessionId, prompt: lastUserPrompt)
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/VibeLight/Watchers/Indexer.swift
git commit -m "feat: persist last user prompt for live sessions during indexing"
```

---

### Task 4: Improve preview card (Feature 1)

Remove the "smart section" (state + detail lines) from the preview card. Show the last **3** exchanges + files.

**Files:**
- Modify: `Sources/VibeLight/Resources/Web/panel.js`

- [ ] **Step 1: Remove state/detail section and bump exchanges to 3**

In `panel.js`, find `window.updatePreview` (~line 761). Replace the state and detail blocks plus the exchanges line:

```js
// REMOVE these blocks entirely:
if (data.state) {
  var stateLine = document.createElement('div');
  stateLine.className = 'preview__state';
  stateLine.textContent = stripMarkdown(stripANSI(data.state));
  previewCard.appendChild(stateLine);
}

if (data.detail) {
  var detailLine = document.createElement('div');
  detailLine.className = 'preview__detail';
  detailLine.textContent = stripMarkdown(stripANSI(data.detail));
  previewCard.appendChild(detailLine);
}

// CHANGE:
var exchanges = (data.exchanges || []).slice(-2);
// TO:
var exchanges = (data.exchanges || []).slice(-3);
```

After the edit, `updatePreview` should start directly with `var exchanges = (data.exchanges || []).slice(-3);` after clearing `previewCard.innerHTML = ''`.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/VibeLight/Resources/Web/panel.js
git commit -m "feat: preview card shows last 3 exchanges and files only, no smart section"
```

---

### Task 5: Show snippet/lastUserPrompt as row title in search results (Feature 2 + Running title)

When a search result has a `snippet` from FTS, display it (stripped of `>>><<<` markers) as the row title. When a session has no smart title (generic title like project name, "Untitled", or empty) and has `lastUserPrompt`, use that as the fallback title. Otherwise use `result.title`.

**Files:**
- Modify: `Sources/VibeLight/Resources/Web/panel.js`

- [ ] **Step 1: Add a helper to pick the display title**

In `panel.js`, after the `stripANSI` function (search for `function stripANSI`), add:

```js
function stripSnippetMarkers(text) {
  return (text || '').replace(/>>>/g, '').replace(/<<</g, '');
}

function isGenericTitle(title, result) {
  if (!title || title === 'Untitled') return true;
  var pName = stripANSI(result.projectName || '');
  if (pName && title === pName) return true;
  return false;
}

function displayTitle(result) {
  // For FTS snippet matches: show the matched text
  if (result.snippet) {
    return stripSnippetMarkers(stripANSI(result.snippet));
  }
  var title = stripANSI(result.title || '');
  // Fallback to last user prompt ONLY when no smart title/summary exists
  if (result.lastUserPrompt && isGenericTitle(title, result)) {
    return stripANSI(result.lastUserPrompt);
  }
  return title;
}
```

- [ ] **Step 2: Use `displayTitle` everywhere `result.title` is rendered**

In `panel.js`, replace all places that render the title:

**In `createRow` (~line 505–506):**
```js
// OLD:
title.textContent = stripANSI(result.title);
// NEW:
title.textContent = displayTitle(result);
```

**In `updateRowContent` (~line 452–454):**
```js
// OLD:
var cleanTitle = stripANSI(result.title);
if (titleEl && titleEl.textContent !== cleanTitle) {
  titleEl.textContent = cleanTitle;
}
// NEW:
var newTitle = displayTitle(result);
if (titleEl && titleEl.textContent !== newTitle) {
  titleEl.textContent = newTitle;
}
```

**In `computeAndShowGhost` (~line 250):** The ghost suggestion should still use `result.title` (the stored name), not the snippet, so no change there.

**In `drillIntoSelectedHistory` (~line 296–297):** Keep `result.title` for the drill-in search. No change.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeLight/Resources/Web/panel.js
git commit -m "feat: show matched snippet or last user prompt as session row title"
```

---

### Task 6: Fix live-session row blink (Bug 2)

When `refreshVisibleResults` fires every 0.5s, if the session's data changes slightly (e.g., `relativeTime` tick), the row content is updated in-place via `updateRowContent`. The blink happens because `updateRowContent` sets `row.className = 'row'` unconditionally on every tick — resetting all classes and causing a brief visual reset even when nothing changed.

**Files:**
- Modify: `Sources/VibeLight/Resources/Web/panel.js`

- [ ] **Step 1: Guard class update in `updateRowContent`**

In `panel.js`, find `function updateRowContent` (~line 438). Replace the class-reset block at the top:

```js
// OLD:
function updateRowContent(row, result, index) {
  // Update state classes
  row.className = 'row';
  var stateClasses = getStateClasses(result);
  for (var i = 0; i < stateClasses.length; i++) {
    row.classList.add(stateClasses[i]);
  }
  if (index === selectedIndex) {
    row.classList.add('row--selected');
  }
  row.dataset.index = index;

// NEW:
function updateRowContent(row, result, index) {
  // Build target className and only apply if different to prevent blink
  var stateClasses = getStateClasses(result);
  var parts = ['row'].concat(stateClasses);
  if (index === selectedIndex) parts.push('row--selected');
  var targetClassName = parts.join(' ');
  if (row.className !== targetClassName) {
    row.className = targetClassName;
  }
  row.dataset.index = index;
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/VibeLight/Resources/Web/panel.js
git commit -m "fix: prevent live session row blink by guarding class updates"
```

---

### Task 7: Fix cursor focus after jumping to a session (Bug 3)

`WindowJumper.activate` uses `options: []` which only brings the app to the front but may not move keyboard focus. We should use `.activateIgnoringOtherApps` to ensure keyboard focus is transferred. The AppleScript TTY path does `activate` but doesn't assert focus. Add `activateIgnoringOtherApps: true` in the NSRunningApplication path, and verify the AppleScript also brings focus.

**Files:**
- Modify: `Sources/VibeLight/Window/WindowJumper.swift`

- [ ] **Step 1: Update `activate` to use `activateIgnoringOtherApps`**

In `WindowJumper.swift`, find `private static func activate(_ application: NSRunningApplication?) -> Bool` (~line 178):

```swift
// OLD:
return application.activate(options: [])

// NEW:
return application.activate(options: .activateIgnoringOtherApps)
```

- [ ] **Step 2: Improve the AppleScript to bring focus to the specific window**

In `jumpViaTerminal`, the current script sets a tab as selected and calls `activate`. Add `set frontmost of terminalWindow to true` and bring it to the front explicitly:

```swift
// OLD script body (after matching the TTY):
set selected of terminalTab to true
set index of terminalWindow to 1
activate
return "ok"

// NEW:
set selected of terminalTab to true
set frontmost of terminalWindow to true
set index of terminalWindow to 1
activate
return "ok"
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeLight/Window/WindowJumper.swift
git commit -m "fix: use activateIgnoringOtherApps so cursor lands in terminal on session jump"
```

---

### Task 8: Run all tests and verify nothing broken

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1 | tail -30
```

Expected: All tests pass. If any fail, diagnose and fix before proceeding.

- [ ] **Step 2: Smoke test manually**

Build and run the app:
```bash
swift build -c release 2>&1 | tail -5
```

Then open the panel and verify:
1. Sessions are ordered most-recently-active first
2. Searching shows transcript snippet as the row title for matching sessions
3. A running (working) session shows the last user prompt as title
4. Preview card shows 3 exchanges + files (no state/detail line)
5. Running session row no longer blinks
6. Clicking a live session brings Terminal to front with cursor in the active window

---

## Self-Review

**Spec coverage check:**
- ✅ Bug 1 (sort order) — Task 1
- ✅ Feature 1 (preview: 3 exchanges, no smart section) — Task 4
- ✅ Feature 2 (snippet as title) — Task 5
- ✅ Bug 2 (blink) — Task 6
- ✅ Running session title = last user prompt — Tasks 2+3+5
- ✅ Bug 3 (cursor focus on jump) — Task 7

**Placeholder scan:** All tasks have concrete code. No TBDs.

**Type consistency:**
- `lastUserPrompt: String?` used consistently in `SearchResult`, `WebBridge`, and `panel.js` as `result.lastUserPrompt`
- `snippet: String?` already on `SearchResult`, added to `WebBridge`, used as `result.snippet` in JS
- `displayTitle(result)` used in both `createRow` and `updateRowContent`
- `updateLastUserPrompt(sessionId:prompt:)` matches signature defined in Task 2 and called in Task 3

**Column index note:** When adding `last_user_prompt` at index 25 in `mapRow`, verify that `last_context_sample_at` is index 24 (0-based) by counting columns in the SELECT list: id(0), tool(1), title(2), project(3), project_name(4), git_branch(5), status(6), started_at(7), pid(8), token_count(9), last_activity_at(10), last_file_mod(11), last_entry_type(12), activity_preview(13), activity_preview_kind(14), snippet(15), health_status(16), health_detail(17), effective_model(18), context_window_tokens(19), context_used_estimate(20), context_percent_estimate(21), context_confidence(22), context_source(23), last_context_sample_at(24), last_user_prompt(25). ✅
