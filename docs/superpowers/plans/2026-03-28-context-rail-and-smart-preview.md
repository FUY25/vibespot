# Context Rail And Smart Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trustworthy current-context telemetry, model visibility, a long context rail in result rows, hover-select behavior, and an adaptive smart preview to the VibeLight search panel.

**Architecture:** Extend the session index to store provider-specific telemetry as normalized session fields, with Codex and Claude parsers extracting the latest usable model/context sample from local logs. Then wire those fields through `SearchResult` and `WebBridge` into a redesigned `panel.js`/`panel.css` row layout, followed by a second slice that upgrades preview extraction and rendering with a state-aware first line plus two rounds and files.

**Tech Stack:** Swift 6, AppKit, WKWebView, SQLite3, Testing, plain JS/CSS in `Sources/VibeLight/Resources/Web`

---

## File Structure

### Existing files to modify

- `Sources/VibeLight/Data/SessionIndex.swift`
  Responsibility: session schema, `SearchResult`, session upsert/search mapping.
- `Sources/VibeLight/UI/WebBridge.swift`
  Responsibility: serialize `SearchResult` into JSON for the web panel.
- `Sources/VibeLight/Parsers/CodexParser.swift`
  Responsibility: parse Codex session files and expose the latest usable model/context sample.
- `Sources/VibeLight/Parsers/ClaudeParser.swift`
  Responsibility: parse Claude session files, model changes, assistant usage, and expose the latest usable model/context sample.
- `Sources/VibeLight/Parsers/Models.swift`
  Responsibility: shared parsed models and provider-neutral telemetry structs.
- `Sources/VibeLight/Parsers/TranscriptTailReader.swift`
  Responsibility: preview extraction, smart first-line derivation, recent rounds, touched files.
- `Sources/VibeLight/Watchers/Indexer.swift`
  Responsibility: index parsed session telemetry into SQLite for both providers.
- `Sources/VibeLight/Watchers/IndexScanner.swift`
  Responsibility: full-scan indexing path; must stay consistent with `Indexer.swift`.
- `Sources/VibeLight/Resources/Web/panel.js`
  Responsibility: result-row DOM shape, hover selection, context rail rendering, adaptive preview rendering.
- `Sources/VibeLight/Resources/Web/panel.css`
  Responsibility: two-column rows, longer rail styling, preview layout.

### Existing tests to modify

- `Tests/VibeLightTests/CodexParserTests.swift`
- `Tests/VibeLightTests/ClaudeParserTests.swift`
- `Tests/VibeLightTests/SessionIndexTests.swift`
- `Tests/VibeLightTests/WebBridgeTests.swift`
- `Tests/VibeLightTests/SearchPanelScriptTests.swift`

### Fixtures to modify or add

- `Tests/VibeLightTests/Fixtures/codex_session.jsonl`
- `Tests/VibeLightTests/Fixtures/claude_session.jsonl`
- `Tests/VibeLightTests/Fixtures/codex_session_index.jsonl`
- `Tests/VibeLightTests/Fixtures/claude_history.jsonl`

### New tests to create

- `Tests/VibeLightTests/TranscriptTailReaderTests.swift`

### New fixture files to create if the existing fixtures become too noisy

- `Tests/VibeLightTests/Fixtures/codex_context_session.jsonl`
- `Tests/VibeLightTests/Fixtures/claude_context_session.jsonl`

---

## Batch 1: Telemetry And Result Rows

### Task 0: Add fuzzy new-session intent ranking and command-style launch parsing

**Files:**
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Sources/VibeLight/Resources/Web/panel.js`
- Modify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`
- Modify: `Tests/VibeLightTests/AppDelegateSelectionRoutingTests.swift`

- [ ] **Step 1: Write the failing tests for fuzzy new-session ranking and command parsing**

```swift
@Test("new-session search intent favors codex action for short fuzzy prefixes")
func newSessionIntentFavorsCodexAction() throws {
    let script = try loadPanelScript()
    #expect(script.contains("looksLikeNewSessionIntent(query)"))
    #expect(script.contains("matchesCodexLaunchIntent(query)"))
}
```

```swift
@MainActor
@Test
func selectingNewCodexActionParsesFlagsAndPrompt() {
    let controller = SearchPanelController()
    let result = SearchResult(
        sessionId: "new-codex",
        tool: "codex",
        title: "New Codex session",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "",
        status: "action",
        startedAt: Date(),
        pid: nil,
        tokenCount: 0,
        lastActivityAt: Date(),
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil,
        healthStatus: "ok",
        healthDetail: "",
        effectiveModel: nil,
        contextWindowTokens: nil,
        contextUsedEstimate: nil,
        contextPercentEstimate: nil,
        contextConfidence: .unknown,
        contextSource: nil
    )

    let parsed = controller.parseNewSessionCommand(from: "new codex --yolo fix auth bug", result: result)
    #expect(parsed.tool == "codex")
    #expect(parsed.flags == ["--yolo"])
    #expect(parsed.prompt == "fix auth bug")
}
```

- [ ] **Step 2: Run the failing tests**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Run: `swift test --filter AppDelegateSelectionRoutingTests 2>&1 | tail -40`

Expected: FAIL because there is no new-session command parser or fuzzy intent helper.

- [ ] **Step 3: Add a focused new-session command parser in `SearchPanelController`**

```swift
struct NewSessionCommand: Equatable {
    let tool: String
    let flags: [String]
    let prompt: String?
}

func parseNewSessionCommand(from query: String, result: SearchResult) -> NewSessionCommand {
    let tokens = query
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

    let tool = result.tool
    let allowedFlags = tool == "codex"
        ? Set(["--yolo", "--help"])
        : Set(["--help"])

    var flags: [String] = []
    var promptTokens: [String] = []

    for token in tokens.dropFirst() {
        if token == tool || token == "new" { continue }
        if promptTokens.isEmpty, allowedFlags.contains(token) {
            flags.append(token)
        } else {
            promptTokens.append(token)
        }
    }

    let prompt = promptTokens.isEmpty ? nil : promptTokens.joined(separator: " ")
    return NewSessionCommand(tool: tool, flags: flags, prompt: prompt)
}
```

- [ ] **Step 4: Bias action rows in `panel.js` for fuzzy new-session intent**

```javascript
function matchesCodexLaunchIntent(query) {
  var q = query.trim().toLowerCase();
  return q === 'co' || q === 'cod' || q.startsWith('new co') || q.startsWith('codex');
}

function matchesClaudeLaunchIntent(query) {
  var q = query.trim().toLowerCase();
  return q === 'cl' || q.startsWith('new cl') || q.startsWith('claude');
}

function looksLikeNewSessionIntent(query) {
  var q = query.trim().toLowerCase();
  return q === 'new' || matchesCodexLaunchIntent(q) || matchesClaudeLaunchIntent(q);
}
```

Use these helpers to keep `New Codex session` / `New Claude session` pinned above ordinary matches when launch intent is detected.

- [ ] **Step 5: Keep launch syntax intentionally narrow**

```swift
// If a token is not a recognized flag, treat the rest as prompt text.
if promptTokens.isEmpty, allowedFlags.contains(token) {
    flags.append(token)
} else {
    promptTokens.append(token)
}
```

This preserves the rule:

- recognized flags stay flags
- remaining text becomes the initial prompt automatically

- [ ] **Step 6: Run the focused tests and a build**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Run: `swift test --filter AppDelegateSelectionRoutingTests 2>&1 | tail -40`

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/UI/SearchPanelController.swift Sources/VibeLight/Resources/Web/panel.js Tests/VibeLightTests/SearchPanelScriptTests.swift Tests/VibeLightTests/AppDelegateSelectionRoutingTests.swift
git commit -m "feat: add fuzzy new-session command parsing"
```

### Task 1: Add normalized session telemetry fields to the data model

**Files:**
- Modify: `Sources/VibeLight/Parsers/Models.swift`
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Tests/VibeLightTests/SessionIndexTests.swift`

- [ ] **Step 1: Write the failing database/search test for normalized telemetry fields**

```swift
@Test
func testSessionSearchReturnsEffectiveModelAndContextTelemetry() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()

    try index.upsertSession(
        id: "ctx-1",
        tool: "codex",
        title: "context telemetry test",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "feat/ctx",
        status: "live",
        startedAt: now,
        pid: 123,
        tokenCount: 41000,
        lastActivityAt: now,
        effectiveModel: "gpt-5.2-codex",
        contextWindowTokens: 258400,
        contextUsedEstimate: 43027,
        contextPercentEstimate: 16,
        contextConfidence: .high,
        contextSource: "codex:last_token_usage",
        lastContextSampleAt: now
    )

    let results = try index.search(query: "context telemetry", includeHistory: true)
    let result = try #require(results.first)

    #expect(result.effectiveModel == "gpt-5.2-codex")
    #expect(result.contextWindowTokens == 258400)
    #expect(result.contextUsedEstimate == 43027)
    #expect(result.contextPercentEstimate == 16)
    #expect(result.contextConfidence == .high)
    #expect(result.contextSource == "codex:last_token_usage")
}
```

- [ ] **Step 2: Run the failing test**

Run: `swift test --filter SessionIndexTests 2>&1 | tail -40`

Expected: FAIL with unknown arguments on `upsertSession` and missing `SearchResult` properties.

- [ ] **Step 3: Add shared telemetry types in `Models.swift`**

```swift
enum ContextConfidence: String, Sendable {
    case high
    case medium
    case low
    case unknown
}

struct SessionContextTelemetry: Sendable {
    let effectiveModel: String?
    let contextWindowTokens: Int?
    let contextUsedEstimate: Int?
    let contextPercentEstimate: Int?
    let contextConfidence: ContextConfidence
    let contextSource: String?
    let lastContextSampleAt: Date?

    static let empty = SessionContextTelemetry(
        effectiveModel: nil,
        contextWindowTokens: nil,
        contextUsedEstimate: nil,
        contextPercentEstimate: nil,
        contextConfidence: .unknown,
        contextSource: nil,
        lastContextSampleAt: nil
    )
}
```

- [ ] **Step 4: Extend `SearchResult`, schema, and row mapping**

```swift
struct SearchResult: Sendable {
    // existing fields...
    let effectiveModel: String?
    let contextWindowTokens: Int?
    let contextUsedEstimate: Int?
    let contextPercentEstimate: Int?
    let contextConfidence: ContextConfidence
    let contextSource: String?
}
```

```swift
try ensureSessionColumnExists(name: "effective_model", definition: "TEXT")
try ensureSessionColumnExists(name: "context_window_tokens", definition: "INTEGER")
try ensureSessionColumnExists(name: "context_used_estimate", definition: "INTEGER")
try ensureSessionColumnExists(name: "context_percent_estimate", definition: "INTEGER")
try ensureSessionColumnExists(name: "context_confidence", definition: "TEXT NOT NULL DEFAULT 'unknown'")
try ensureSessionColumnExists(name: "context_source", definition: "TEXT")
try ensureSessionColumnExists(name: "last_context_sample_at", definition: "REAL")
```

```swift
func upsertSession(
    // existing args...
    effectiveModel: String? = nil,
    contextWindowTokens: Int? = nil,
    contextUsedEstimate: Int? = nil,
    contextPercentEstimate: Int? = nil,
    contextConfidence: ContextConfidence = .unknown,
    contextSource: String? = nil,
    lastContextSampleAt: Date? = nil
) throws
```

- [ ] **Step 5: Run the test and the broader index tests**

Run: `swift test --filter SessionIndexTests 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Parsers/Models.swift Sources/VibeLight/Data/SessionIndex.swift Tests/VibeLightTests/SessionIndexTests.swift
git commit -m "feat: add normalized context telemetry fields"
```

### Task 2: Parse and index Codex model/context telemetry

**Files:**
- Modify: `Sources/VibeLight/Parsers/CodexParser.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Modify: `Sources/VibeLight/Watchers/IndexScanner.swift`
- Modify: `Tests/VibeLightTests/CodexParserTests.swift`
- Modify or Create: `Tests/VibeLightTests/Fixtures/codex_context_session.jsonl`

- [ ] **Step 1: Write the failing Codex parser test**

```swift
@Test
func testParseCodexSessionFileExtractsLatestUsableContextTelemetry() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "codex_context_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (meta, messages, telemetry) = try CodexParser.parseSessionFile(url: fixtureURL)
    let parsedMeta = try #require(meta)
    let parsedTelemetry = try #require(telemetry)

    #expect(parsedMeta.id == "codex-ctx-001")
    #expect(parsedTelemetry.effectiveModel == "gpt-5.2-codex")
    #expect(parsedTelemetry.contextWindowTokens == 258400)
    #expect(parsedTelemetry.contextUsedEstimate == 43027)
    #expect(parsedTelemetry.contextPercentEstimate == 16)
    #expect(parsedTelemetry.contextConfidence == .high)
    #expect(parsedTelemetry.contextSource == "codex:last_token_usage")
    #expect(messages.count > 0)
}
```

- [ ] **Step 2: Create the focused Codex fixture and run the failing test**

```json
{"timestamp":"2026-01-14T10:06:14.970Z","type":"turn_context","payload":{"cwd":"/Users/me/project","model":"gpt-5.2-codex","effort":"high","summary":"auto"}}
{"timestamp":"2026-01-14T10:06:16.713Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":443420,"cached_input_tokens":399104,"output_tokens":931,"reasoning_output_tokens":64,"total_tokens":444351},"last_token_usage":{"input_tokens":42977,"cached_input_tokens":41856,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":43027},"model_context_window":258400}}}
{"timestamp":"2026-01-14T10:06:18.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Running quick checks before final answer."}]}}
```

Run: `swift test --filter CodexParserTests 2>&1 | tail -40`

Expected: FAIL because `parseSessionFile` does not return telemetry.

- [ ] **Step 3: Extend Codex parser output and compute telemetry**

```swift
static func parseSessionFile(url: URL) throws -> (
    meta: CodexSessionMeta?,
    messages: [ParsedMessage],
    telemetry: SessionContextTelemetry?
) {
    var latestModel: String?
    var latestTelemetry: SessionContextTelemetry?

    // inside turn_context:
    latestModel = payload["model"] as? String ?? latestModel

    // inside token_count:
    let info = payload["info"] as? [String: Any] ?? [:]
    let last = info["last_token_usage"] as? [String: Any] ?? [:]
    let inputTokens = intValue(last["input_tokens"]) ?? 0
    let cachedTokens = intValue(last["cached_input_tokens"]) ?? 0
    let window = intValue(info["model_context_window"])
    let used = inputTokens + cachedTokens
    let percent = window.map { max(0, min(100, Int((Double(used) / Double($0)) * 100.0))) }

    latestTelemetry = SessionContextTelemetry(
        effectiveModel: latestModel,
        contextWindowTokens: window,
        contextUsedEstimate: used,
        contextPercentEstimate: percent,
        contextConfidence: (window != nil && used > 0) ? .high : .unknown,
        contextSource: "codex:last_token_usage",
        lastContextSampleAt: timestamp
    )
}
```

- [ ] **Step 4: Persist Codex telemetry in both indexing paths**

```swift
let (meta, messages, telemetry) = try CodexParser.parseSessionFile(url: url)

try? sessionIndex.upsertSession(
    // existing args...
    effectiveModel: telemetry?.effectiveModel,
    contextWindowTokens: telemetry?.contextWindowTokens,
    contextUsedEstimate: telemetry?.contextUsedEstimate,
    contextPercentEstimate: telemetry?.contextPercentEstimate,
    contextConfidence: telemetry?.contextConfidence ?? .unknown,
    contextSource: telemetry?.contextSource,
    lastContextSampleAt: telemetry?.lastContextSampleAt
)
```

- [ ] **Step 5: Run parser and index tests**

Run: `swift test --filter CodexParserTests 2>&1 | tail -40`

Run: `swift test --filter SessionIndexTests 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Parsers/CodexParser.swift Sources/VibeLight/Watchers/Indexer.swift Sources/VibeLight/Watchers/IndexScanner.swift Tests/VibeLightTests/CodexParserTests.swift Tests/VibeLightTests/Fixtures/codex_context_session.jsonl
git commit -m "feat: parse and persist codex context telemetry"
```

### Task 3: Parse and index Claude model/context telemetry conservatively

**Files:**
- Modify: `Sources/VibeLight/Parsers/ClaudeParser.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Modify: `Sources/VibeLight/Watchers/IndexScanner.swift`
- Modify: `Tests/VibeLightTests/ClaudeParserTests.swift`
- Modify or Create: `Tests/VibeLightTests/Fixtures/claude_context_session.jsonl`

- [ ] **Step 1: Write the failing Claude parser tests for known and unknown states**

```swift
@Test
func testParseClaudeSessionFileExtractsKnownContextTelemetry() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_context_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(messages.count > 0)
    #expect(parsedTelemetry.effectiveModel == "claude-haiku-4-5")
    #expect(parsedTelemetry.contextWindowTokens == 200_000)
    #expect(parsedTelemetry.contextUsedEstimate == 60_777)
    #expect(parsedTelemetry.contextPercentEstimate == 30)
    #expect(parsedTelemetry.contextConfidence == .medium)
}

@Test
func testParseClaudeSessionFileMarksContextUnknownAfterModelSwitchWithoutAssistantTurn() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_context_session_model_switch", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (_, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(parsedTelemetry.effectiveModel == "claude-opus-4-6")
    #expect(parsedTelemetry.contextPercentEstimate == nil)
    #expect(parsedTelemetry.contextConfidence == .unknown)
}
```

- [ ] **Step 2: Add the fixture lines and run the failing tests**

```json
{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to Haiku 4.5</local-command-stdout>"},"timestamp":"2026-03-26T04:08:19.379Z","sessionId":"claude-ctx-001","cwd":"/Users/me/project"}
{"type":"assistant","timestamp":"2026-03-26T04:33:07.676Z","sessionId":"claude-ctx-001","cwd":"/Users/me/project","message":{"model":"claude-haiku-4-5","role":"assistant","content":[{"type":"text","text":"I can help with that."}],"usage":{"input_tokens":30394,"cache_creation_input_tokens":0,"cache_read_input_tokens":30383,"output_tokens":152}}}
```

Run: `swift test --filter ClaudeParserTests 2>&1 | tail -60`

Expected: FAIL because Claude parser does not expose telemetry yet.

- [ ] **Step 3: Extend Claude parser to return telemetry and model-switch state**

```swift
static func parseSessionFile(url: URL) throws -> (
    messages: [ParsedMessage],
    telemetry: SessionContextTelemetry?
) {
    var messages: [ParsedMessage] = []
    var latestTelemetry: SessionContextTelemetry?
    var pendingModelSwitch: String?

    if type == "user", let commandText = extractUserOnlyText(from: message["content"]), commandText.lowercased().contains("set model to") {
        pendingModelSwitch = normalizedClaudeModel(from: commandText)
        latestTelemetry = SessionContextTelemetry(
            effectiveModel: pendingModelSwitch,
            contextWindowTokens: nil,
            contextUsedEstimate: nil,
            contextPercentEstimate: nil,
            contextConfidence: .unknown,
            contextSource: "claude:model_switch_pending",
            lastContextSampleAt: timestamp
        )
    }

    if type == "assistant" {
        let model = message["model"] as? String
        let usage = message["usage"] as? [String: Any] ?? [:]
        let input = intValue(usage["input_tokens"]) ?? 0
        let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
        let cacheCreate = intValue(usage["cache_creation_input_tokens"]) ?? 0
        let used = input + cacheRead + cacheCreate
        let window = inferredClaudeContextWindow(for: model, used: used)
        let percent = window.map { max(0, min(100, Int((Double(used) / Double($0)) * 100.0))) }

        latestTelemetry = SessionContextTelemetry(
            effectiveModel: model,
            contextWindowTokens: window,
            contextUsedEstimate: used,
            contextPercentEstimate: percent,
            contextConfidence: window == nil ? .unknown : .medium,
            contextSource: "claude:assistant_usage",
            lastContextSampleAt: timestamp
        )
        pendingModelSwitch = nil
    }
}
```

- [ ] **Step 4: Persist Claude telemetry through both indexing paths**

```swift
let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: url)

try? sessionIndex.upsertSession(
    // existing args...
    effectiveModel: telemetry?.effectiveModel,
    contextWindowTokens: telemetry?.contextWindowTokens,
    contextUsedEstimate: telemetry?.contextUsedEstimate,
    contextPercentEstimate: telemetry?.contextPercentEstimate,
    contextConfidence: telemetry?.contextConfidence ?? .unknown,
    contextSource: telemetry?.contextSource,
    lastContextSampleAt: telemetry?.lastContextSampleAt
)
```

- [ ] **Step 5: Run Claude parser tests**

Run: `swift test --filter ClaudeParserTests 2>&1 | tail -60`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Parsers/ClaudeParser.swift Sources/VibeLight/Watchers/Indexer.swift Sources/VibeLight/Watchers/IndexScanner.swift Tests/VibeLightTests/ClaudeParserTests.swift Tests/VibeLightTests/Fixtures/claude_context_session.jsonl
git commit -m "feat: parse and persist claude context telemetry"
```

### Task 4: Expose telemetry to the web layer and redesign result rows

**Files:**
- Modify: `Sources/VibeLight/UI/WebBridge.swift`
- Modify: `Sources/VibeLight/Resources/Web/panel.js`
- Modify: `Sources/VibeLight/Resources/Web/panel.css`
- Modify: `Tests/VibeLightTests/WebBridgeTests.swift`
- Modify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`

- [ ] **Step 1: Write the failing serialization and script tests**

```swift
@MainActor
@Test("resultToJSON includes model and context telemetry fields")
func resultToJSONIncludesContextFields() {
    let result = SearchResult(
        sessionId: "ctx-1",
        tool: "codex",
        title: "test",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "feat/ctx",
        status: "live",
        startedAt: Date(timeIntervalSince1970: 1_711_600_000),
        pid: 1,
        tokenCount: 41000,
        lastActivityAt: Date(timeIntervalSince1970: 1_711_600_100),
        activityPreview: nil,
        activityStatus: .working,
        snippet: nil,
        healthStatus: "ok",
        healthDetail: "",
        effectiveModel: "gpt-5.2-codex",
        contextWindowTokens: 258400,
        contextUsedEstimate: 43027,
        contextPercentEstimate: 16,
        contextConfidence: .high,
        contextSource: "codex:last_token_usage"
    )

    let json = WebBridge.resultToJSON(result)
    #expect(json["effectiveModel"] as? String == "gpt-5.2-codex")
    #expect(json["contextPercentEstimate"] as? Int == 16)
    #expect(json["contextUsedEstimate"] as? Int == 43027)
    #expect(json["contextConfidence"] as? String == "high")
}
```

```swift
@Test("panel script renders hover selection and context rail helpers")
func panelScriptIncludesHoverSelectionAndContextHelpers() throws {
    let script = try loadPanelScript()
    #expect(script.contains("row.addEventListener('mouseenter'"))
    #expect(script.contains("formatContextLabel(result)"))
    #expect(script.contains("row__path"))
    #expect(script.contains("row__context-rail"))
}
```

- [ ] **Step 2: Run the failing tests**

Run: `swift test --filter WebBridgeTests 2>&1 | tail -40`

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Expected: FAIL due to missing JSON keys and DOM helpers.

- [ ] **Step 3: Serialize telemetry and model fields into result JSON**

```swift
dict["effectiveModel"] = result.effectiveModel
dict["contextWindowTokens"] = result.contextWindowTokens
dict["contextUsedEstimate"] = result.contextUsedEstimate
dict["contextPercentEstimate"] = result.contextPercentEstimate
dict["contextConfidence"] = result.contextConfidence.rawValue
dict["contextSource"] = result.contextSource
```

- [ ] **Step 4: Replace the row DOM shape and add hover selection**

```javascript
function formatModelMeta(result) {
  var model = result.effectiveModel || 'Model unknown';
  return model + ' · ' + (result.relativeTime || '');
}

function formatContextLabel(result) {
  var percent = result.contextPercentEstimate;
  var used = result.contextUsedEstimate;
  var confidence = result.contextConfidence || 'unknown';
  var percentText = percent == null ? '?' : (confidence === 'medium' ? '~' + percent + '%' : percent + '%');
  var usedText = used == null ? '' : ' ' + formatCompactTokens(used);
  return (percentText + usedText).trim();
}

row.addEventListener('mouseenter', function() {
  selectedIndex = index;
  updateSelection();
  updateActionHint();
  scheduleDwell();
});
```

- [ ] **Step 5: Add the two-column row CSS and long rail styling**

```css
.row__body {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(220px, 320px);
  grid-template-rows: auto auto;
  column-gap: 14px;
  row-gap: 4px;
}

.row__path {
  grid-column: 2;
  grid-row: 1;
  justify-self: end;
  min-width: 0;
  font-size: 11px;
  color: var(--label-tertiary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.row__context {
  grid-column: 2;
  grid-row: 2;
  display: flex;
  align-items: center;
  gap: 8px;
}

.row__context-rail {
  flex: 1;
  height: 4px;
  border-radius: 999px;
  background: rgba(255,255,255,0.08);
  overflow: hidden;
}
```

- [ ] **Step 6: Run JS-facing tests and a build**

Run: `swift test --filter WebBridgeTests 2>&1 | tail -40`

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/UI/WebBridge.swift Sources/VibeLight/Resources/Web/panel.js Sources/VibeLight/Resources/Web/panel.css Tests/VibeLightTests/WebBridgeTests.swift Tests/VibeLightTests/SearchPanelScriptTests.swift
git commit -m "feat: show model and context rail in search results"
```

---

## Batch 2: Smart Preview

### Task 5: Upgrade transcript-tail parsing to return a smart first line and compact rounds

**Files:**
- Modify: `Sources/VibeLight/Parsers/TranscriptTailReader.swift`
- Create: `Tests/VibeLightTests/TranscriptTailReaderTests.swift`
- Modify or Create: `Tests/VibeLightTests/Fixtures/claude_context_session.jsonl`
- Modify or Create: `Tests/VibeLightTests/Fixtures/codex_context_session.jsonl`

- [ ] **Step 1: Write the failing preview extraction tests**

```swift
@Test
func testPreviewPrefersWaitingQuestionForFirstLine() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_context_session_waiting", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Waiting: Which layout do you prefer?")
    #expect(preview.exchanges.count == 2)
}

@Test
func testPreviewPrefersErrorSummaryForFirstLine() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_context_session_error", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Error: swift build failed in SearchPanelController.swift")
}
```

- [ ] **Step 2: Run the failing tests**

Run: `swift test --filter TranscriptTailReaderTests 2>&1 | tail -40`

Expected: FAIL because `PreviewData` has no `headline` and the reader does not classify state yet.

- [ ] **Step 3: Extend preview data and classify the first line**

```swift
struct PreviewData: Sendable {
    let headline: String?
    let exchanges: [PreviewExchange]
    let files: [String]
}

private static func deriveHeadline(
    from records: [[String: Any]],
    exchanges: [PreviewExchange]
) -> String? {
    if let waiting = latestWaitingPrompt(in: records) {
        return "Waiting: \(waiting)"
    }
    if let error = latestErrorSummary(in: records) {
        return "Error: \(error)"
    }
    if let action = latestWorkAction(in: records) {
        return action
    }
    if let latestUser = exchanges.last(where: { $0.role == "user" })?.text {
        return "Current task: \(latestUser)"
    }
    return nil
}
```

- [ ] **Step 4: Limit exchange selection to two meaningful rounds and keep files recent-first**

```swift
let meaningfulExchanges = exchanges
    .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    .suffix(exchangeCount)

return PreviewData(
    headline: deriveHeadline(from: parsedRecords, exchanges: Array(meaningfulExchanges)),
    exchanges: Array(meaningfulExchanges),
    files: Array(files.prefix(5))
)
```

- [ ] **Step 5: Run the new tests**

Run: `swift test --filter TranscriptTailReaderTests 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Parsers/TranscriptTailReader.swift Tests/VibeLightTests/TranscriptTailReaderTests.swift Tests/VibeLightTests/Fixtures/claude_context_session_waiting.jsonl Tests/VibeLightTests/Fixtures/claude_context_session_error.jsonl
git commit -m "feat: derive smart preview headline from transcript tails"
```

### Task 6: Redesign preview rendering and live refresh behavior

**Files:**
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Sources/VibeLight/Resources/Web/panel.js`
- Modify: `Sources/VibeLight/Resources/Web/panel.css`
- Modify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`

- [ ] **Step 1: Write the failing script test for adaptive preview sections**

```swift
@Test
func previewScriptIncludesHeadlineAndTwoRoundSections() throws {
    let script = try loadPanelScript()
    #expect(script.contains("data.headline"))
    #expect(script.contains("preview__headline"))
    #expect(script.contains("preview__rounds"))
    #expect(script.contains("preview__files"))
}
```

- [ ] **Step 2: Run the failing script test**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Expected: FAIL because preview rendering is still tail-dump based.

- [ ] **Step 3: Include `headline` in preview JSON and keep controller behavior stable**

```swift
let dict: [String: Any] = [
    "headline": preview.headline as Any,
    "exchanges": exchangeArray,
    "files": preview.files,
]
```

```swift
let preview = TranscriptTailReader.read(fileURL: fileURL, exchangeCount: 2)
```

- [ ] **Step 4: Replace preview DOM rendering with adaptive sections**

```javascript
if (data.headline) {
  var headline = document.createElement('div');
  headline.className = 'preview__headline';
  headline.textContent = stripMarkdown(stripANSI(data.headline));
  previewCard.appendChild(headline);
}

var rounds = document.createElement('div');
rounds.className = 'preview__rounds';
// append up to two exchange blocks here
previewCard.appendChild(rounds);
```

- [ ] **Step 5: Add preview styling that favors headline, then rounds, then files**

```css
.preview {
  width: 440px;
}

.preview__headline {
  font-size: 13px;
  line-height: 1.35;
  color: var(--label);
  margin-bottom: 10px;
}

.preview__rounds {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 12px;
}
```

- [ ] **Step 6: Run the script test and build**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -40`

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/UI/SearchPanelController.swift Sources/VibeLight/Resources/Web/panel.js Sources/VibeLight/Resources/Web/panel.css Tests/VibeLightTests/SearchPanelScriptTests.swift
git commit -m "feat: redesign preview with adaptive headline and compact rounds"
```

### Task 7: Final verification across parser, storage, script, and build surfaces

**Files:**
- Modify if needed: any files touched above to fix integration gaps
- Test: `Tests/VibeLightTests/CodexParserTests.swift`
- Test: `Tests/VibeLightTests/ClaudeParserTests.swift`
- Test: `Tests/VibeLightTests/SessionIndexTests.swift`
- Test: `Tests/VibeLightTests/WebBridgeTests.swift`
- Test: `Tests/VibeLightTests/SearchPanelScriptTests.swift`
- Test: `Tests/VibeLightTests/TranscriptTailReaderTests.swift`

- [ ] **Step 1: Run the focused verification suite**

Run:

```bash
swift test --filter CodexParserTests 2>&1 | tail -40
swift test --filter ClaudeParserTests 2>&1 | tail -60
swift test --filter SessionIndexTests 2>&1 | tail -40
swift test --filter WebBridgeTests 2>&1 | tail -40
swift test --filter SearchPanelScriptTests 2>&1 | tail -40
swift test --filter TranscriptTailReaderTests 2>&1 | tail -40
```

Expected: all PASS.

- [ ] **Step 2: Run the full test suite**

Run: `swift test 2>&1 | tail -80`

Expected: PASS with no new failures.

- [ ] **Step 3: Run a final build**

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 4: Fix any integration mismatches found during the full suite**

Likely issues to check:

```swift
// SearchResult initializer call sites in tests may need the new telemetry fields.
effectiveModel: nil,
contextWindowTokens: nil,
contextUsedEstimate: nil,
contextPercentEstimate: nil,
contextConfidence: .unknown,
contextSource: nil
```

```javascript
// Ensure row rebuild and in-place updates both set the new path/context fields.
if (metaEl) metaEl.textContent = formatModelMeta(result);
if (pathEl) pathEl.textContent = formatDisplayPath(result.project);
```

- [ ] **Step 5: Commit the verification fixes**

```bash
git add -A
git commit -m "test: verify context rail and smart preview integration"
```

---

## Self-Review

### Spec coverage

- Fuzzy new-session ranking and command-like launch parsing: covered in Task 0.
- Model name in result rows: covered in Task 4.
- Long visible context rail with compact label: covered in Task 4.
- Honest Codex and Claude telemetry rules: covered in Tasks 1, 2, and 3.
- Hover-select interaction: covered in Task 4.
- Smart preview first line, two rounds, files: covered in Tasks 5 and 6.
- Unknown-state rendering: covered in Tasks 1, 3, and 4.

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Every task contains file paths, tests, commands, and concrete code snippets.

### Type consistency

- Shared telemetry state is introduced once in `Models.swift` and then threaded through `SessionIndex`, parsers, and `WebBridge`.
- Both indexing paths are explicitly included so scanner and live indexer do not diverge.
