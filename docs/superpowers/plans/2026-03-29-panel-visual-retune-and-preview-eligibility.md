# Panel Visual Retune And Preview Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved panel retune: full-width titles, bottom-right path, token-only meta, no row status dots, a two-line preview header with provider-correct state for Codex and Claude, reliable preview opening for finished rows, and a wider native preview pane.

**Architecture:** Keep the session/search pipeline intact and narrow the work to three seams: `TranscriptTailReader` produces structured preview state + detail instead of a single headline string, `SearchPanelController` merges live runtime state into that preview for correctness and expands the native panel width, and `panel.js` / `panel.css` simplify the row and preview DOM to the new visual structure. Existing session telemetry fields remain in the data model, but this slice removes the rail and rough percentage from the UI.

**Tech Stack:** Swift 6, AppKit, WKWebView, Swift Testing, plain JavaScript, plain CSS

---

## Scope Note

This plan supersedes the rail-specific parts of:

- `docs/superpowers/plans/2026-03-28-context-rail-and-smart-preview.md`

for the current slice only.

The parsing/indexing telemetry work stays in place, but the UI now shows only compact token count when it is trustworthy enough to display cleanly.

## File Structure

### Existing files to modify

- `Sources/VibeLight/Parsers/TranscriptTailReader.swift`
  Responsibility: derive structured preview state/detail plus recent exchanges and files from Codex and Claude transcript tails.
- `Sources/VibeLight/UI/SearchPanelController.swift`
  Responsibility: merge runtime row state with transcript-derived preview data, widen the native preview pane, and push preview payloads into the web view.
- `Sources/VibeLight/Resources/Web/panel.js`
  Responsibility: render the simplified row layout, remove row dots/context rail DOM, render state/detail preview header, and fix dwell scheduling for already-selected rows.
- `Sources/VibeLight/Resources/Web/panel.css`
  Responsibility: match the approved row and preview visual structure, remove boxed preview cards, and remove unused context-rail/status-dot styling.

### Existing tests to modify

- `Tests/VibeLightTests/TranscriptTailReaderTests.swift`
- `Tests/VibeLightTests/SearchPanelScriptTests.swift`

### New tests to create

- `Tests/VibeLightTests/SearchPanelControllerPreviewTests.swift`

---

## Task 1: Reshape Preview Data Into State + Detail

**Files:**
- Modify: `Sources/VibeLight/Parsers/TranscriptTailReader.swift`
- Modify: `Tests/VibeLightTests/TranscriptTailReaderTests.swift`

- [ ] **Step 1: Rewrite the failing transcript preview tests to assert `state` + `detail` instead of `headline`**

Update the existing waiting/error/task tests so they fail on the current `headline` shape and describe the new provider-neutral preview contract.

```swift
@Test
func testPreviewUsesQuestionStateForWaitingQuestion() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.state == "Question")
    #expect(preview.detail == "Which layout do you prefer?")
    #expect(preview.exchanges.count == 2)
}

@Test
func testPreviewUsesErrorStateForAssistantFailure() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_error",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.state == "Error")
    #expect(preview.detail == "swift build failed in SearchPanelController.swift")
}

@Test
func testPreviewUsesTaskStateWhenNoStrongerStateExists() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_state_neutral_newer_than_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.state == "Task")
    #expect(preview.detail == "Please proceed with the parser update and tests.")
}
```

- [ ] **Step 2: Add one Codex-specific state test and one JSON serialization test**

These two tests protect the provider-neutral state rules and the web payload contract.

```swift
@Test
func testPreviewUsesWorkingStateForCodexAssistantAction() throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Running a narrower retry now."}]}}"#
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.state == "Working")
    #expect(preview.detail == "Running a narrower retry now.")
}

@Test
func testPreviewJSONIncludesStateAndDetailKeys() throws {
    let preview = PreviewData(
        state: "Question",
        detail: "Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?",
        exchanges: [],
        files: []
    )

    let json = TranscriptTailReader.previewToJSONString(preview)
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["state"] as? String == "Question")
    #expect(object["detail"] as? String == "Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?")
    #expect(object["headline"] == nil)
}
```

- [ ] **Step 3: Run the tests to confirm they fail on the old `headline` implementation**

Run: `swift test --filter TranscriptTailReaderTests 2>&1 | tail -60`

Expected: FAIL because `PreviewData` still exposes `headline`, and `previewToJSONString` still emits `"headline"`.

- [ ] **Step 4: Replace `headline` with structured `state` + `detail` in `TranscriptTailReader.swift`**

Implement a tiny provider-neutral state model and convert the old headline derivation into a structured header.

```swift
struct PreviewData: Sendable {
    let state: String?
    let detail: String?
    let exchanges: [PreviewExchange]
    let files: [String]
}

private enum PreviewHeader {
    case question(String)
    case waiting(String)
    case error(String)
    case working(String)
    case task(String)

    var state: String {
        switch self {
        case .question: return "Question"
        case .waiting: return "Waiting"
        case .error: return "Error"
        case .working: return "Working"
        case .task: return "Task"
        }
    }

    var detail: String {
        switch self {
        case .question(let text), .waiting(let text), .error(let text), .working(let text), .task(let text):
            return text
        }
    }
}
```

Use the existing signal logic, but map it into explicit states:

```swift
private static func derivePreviewHeader(
    from messagesNewestFirst: [TailMessage],
    exchanges: [PreviewExchange]
) -> PreviewHeader? {
    if let signal = latestStateSignal(in: messagesNewestFirst) {
        switch signal {
        case .waiting(let prompt):
            return prompt.contains("?") ? .question(prompt) : .waiting(prompt)
        case .error(let summary):
            return .error(summary)
        case .action(let action):
            return .working(action)
        }
    }

    if let latestUserAsk = latestMeaningfulUserAsk(in: messagesNewestFirst, exchanges: exchanges) {
        return .task(latestUserAsk)
    }

    return nil
}
```

Update the JSON output contract:

```swift
let dict: [String: Any] = [
    "state": preview.state ?? NSNull(),
    "detail": preview.detail ?? NSNull(),
    "exchanges": exchangeArray,
    "files": preview.files,
]
```

- [ ] **Step 5: Run the transcript preview tests again**

Run: `swift test --filter TranscriptTailReaderTests 2>&1 | tail -60`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Parsers/TranscriptTailReader.swift Tests/VibeLightTests/TranscriptTailReaderTests.swift
git commit -m "feat: structure preview header as state and detail"
```

---

## Task 2: Merge Live State Correctly And Fix Preview Opening

**Files:**
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Sources/VibeLight/Resources/Web/panel.js`
- Modify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`
- Create: `Tests/VibeLightTests/SearchPanelControllerPreviewTests.swift`

- [ ] **Step 1: Add failing Swift tests for runtime preview-state merging**

Create a focused pure-function test file so live Codex and live Claude state logic can be verified without spinning up `WKWebView`.

```swift
import Foundation
import Testing
@testable import VibeLight

@MainActor
struct SearchPanelControllerPreviewTests {
    @Test
    func liveClaudeAssistantQuestionBecomesQuestionState() {
        let result = SearchResult(
            sessionId: "claude-live",
            tool: "claude",
            title: "Need input",
            project: "/tmp/project",
            projectName: "project",
            gitBranch: "",
            status: "live",
            startedAt: .now,
            pid: 1,
            tokenCount: 12_000,
            lastActivityAt: .now,
            activityPreview: ActivityPreview(text: "Which layout do you prefer?", kind: .assistant),
            activityStatus: .waiting,
            snippet: nil,
            healthStatus: "ok",
            healthDetail: ""
        )
        let tail = PreviewData(state: "Task", detail: "Older fallback detail", exchanges: [], files: [])

        let merged = SearchPanelController.mergedPreviewData(result: result, tail: tail)

        #expect(merged.state == "Question")
        #expect(merged.detail == "Which layout do you prefer?")
    }

    @Test
    func liveCodexToolActivityBecomesWorkingState() {
        let result = SearchResult(
            sessionId: "codex-live",
            tool: "codex",
            title: "Building",
            project: "/tmp/project",
            projectName: "project",
            gitBranch: "",
            status: "live",
            startedAt: .now,
            pid: 2,
            tokenCount: 24_000,
            lastActivityAt: .now,
            activityPreview: ActivityPreview(text: "▶ Running swift build", kind: .tool),
            activityStatus: .working,
            snippet: nil,
            healthStatus: "ok",
            healthDetail: ""
        )
        let tail = PreviewData(state: "Task", detail: "Older fallback detail", exchanges: [], files: [])

        let merged = SearchPanelController.mergedPreviewData(result: result, tail: tail)

        #expect(merged.state == "Working")
        #expect(merged.detail == "Running swift build")
    }
}
```

- [ ] **Step 2: Add failing JS tests for preview DOM and dwell scheduling**

Update `SearchPanelScriptTests.swift` to cover the two regressions called out in review: the preview header shape and previews not opening for already-selected/finished rows.

```swift
@Test("preview renders state and detail in separate top lines")
func previewRendersStateAndDetailInSeparateTopLines() throws {
    let context = try makePanelScriptContext()
    let payload = #"""
    {
      "state": "Question",
      "detail": "Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?",
      "exchanges": [],
      "files": []
    }
    """#

    _ = context.evaluateScript("window.updatePreview(\(payload));")

    #expect(try invokeString("__queryFirstText(__els.previewCard, 'preview__state')", in: context) == "Question")
    #expect(try invokeString("__queryFirstText(__els.previewCard, 'preview__detail')", in: context) == "Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?")
}

@Test("mouseenter on already-selected finished row still requests preview")
func mouseEnterOnAlreadySelectedFinishedRowStillRequestsPreview() throws {
    let context = try makePanelScriptContext()
    let payload = #"""
    [{
      "sessionId": "sess-finished",
      "tool": "claude",
      "title": "Done",
      "project": "/tmp/project",
      "projectName": "project",
      "gitBranch": "",
      "status": "closed",
      "startedAt": "2026-03-29T00:00:00Z",
      "tokenCount": 1200,
      "lastActivityAt": "2026-03-29T00:01:00Z",
      "activityStatus": "closed",
      "relativeTime": "1m ago",
      "healthStatus": "ok",
      "healthDetail": ""
    }]
    """#

    _ = context.evaluateScript("window.updateResults(\(payload));")
    _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter'); __runAllTimeouts();")

    #expect(try invokeBool("window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-finished'; })", in: context))
}
```

- [ ] **Step 3: Run the focused tests to watch them fail**

Run: `swift test --filter SearchPanelControllerPreviewTests 2>&1 | tail -60`

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -80`

Expected: FAIL because `SearchPanelController` has no merge helper, `panel.js` still renders `preview__headline`, and `mouseenter` on an already-selected row short-circuits before scheduling dwell.

- [ ] **Step 4: Add a pure merge helper in `SearchPanelController.swift` and widen the native pane**

Implement a static merge point that prefers runtime state when it is clearly stronger than transcript fallback.

```swift
extension SearchPanelController {
    static func mergedPreviewData(result: SearchResult, tail: PreviewData) -> PreviewData {
        if result.healthStatus == "error" {
            let detail = result.healthDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                return PreviewData(state: "Error", detail: detail, exchanges: tail.exchanges, files: tail.files)
            }
        }

        if result.activityStatus == .working, let preview = result.activityPreview {
            let detail = cleanedActivityPreviewText(preview.text)
            if !detail.isEmpty {
                return PreviewData(state: "Working", detail: detail, exchanges: tail.exchanges, files: tail.files)
            }
        }

        if result.activityStatus == .waiting, let preview = result.activityPreview {
            let detail = cleanedActivityPreviewText(preview.text)
            if !detail.isEmpty {
                let state = detail.contains("?") ? "Question" : "Waiting"
                return PreviewData(state: state, detail: detail, exchanges: tail.exchanges, files: tail.files)
            }
        }

        return tail
    }

    private static func cleanedActivityPreviewText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "✎ ", with: "")
            .replacingOccurrences(of: "▶ ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Use the helper in preview delivery:

```swift
func webBridge(_ bridge: WebBridge, didRequestPreview sessionId: String) {
    guard let fileURL = findSessionFile(sessionId: sessionId),
          let result = results.first(where: { $0.sessionId == sessionId }) else { return }

    Task.detached(priority: .utility) { [weak self] in
        let tail = TranscriptTailReader.read(fileURL: fileURL)
        let preview = await MainActor.run { SearchPanelController.mergedPreviewData(result: result, tail: tail) }
        let json = TranscriptTailReader.previewToJSONString(preview)
        await MainActor.run { [weak self] in
            guard let self, self.isWebViewReady else { return }
            let escaped = self.escapeForSingleQuotedJavaScriptString(json)
            self.webView.evaluateJavaScript("updatePreview('\(escaped)')", completionHandler: nil)
        }
    }
}
```

Increase the native width so it actually fits the preview pane:

```swift
private let previewExtraWidth: CGFloat = 470
```

- [ ] **Step 5: Update `panel.js` so preview opens reliably and renders `state` + `detail`**

Fix dwell scheduling for rows that are already selected, and switch the preview DOM to two top lines.

```javascript
row.addEventListener('click', function() {
  selectedIndex = index;
  updateSelection();
  updateActionHint();
  scheduleDwell();
});

row.addEventListener('mouseenter', function() {
  if (selectedIndex !== index) {
    selectedIndex = index;
    updateSelection();
    updateActionHint();
  }
  scheduleDwell();
});
```

```javascript
if (data.state) {
  var state = document.createElement('div');
  state.className = 'preview__state';
  state.textContent = stripMarkdown(stripANSI(data.state));
  previewCard.appendChild(state);
}

if (data.detail) {
  var detail = document.createElement('div');
  detail.className = 'preview__detail';
  detail.textContent = stripMarkdown(stripANSI(data.detail));
  previewCard.appendChild(detail);
}
```

Leave the `exchanges` and `files` payloads intact for now; only the top structure changes in this task.

- [ ] **Step 6: Run the focused tests and a build**

Run: `swift test --filter SearchPanelControllerPreviewTests 2>&1 | tail -60`

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -80`

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/UI/SearchPanelController.swift Sources/VibeLight/Resources/Web/panel.js Tests/VibeLightTests/SearchPanelScriptTests.swift Tests/VibeLightTests/SearchPanelControllerPreviewTests.swift
git commit -m "fix: make preview state correct and preview opening reliable"
```

---

## Task 3: Simplify The Result Rows And Flatten The Preview Styling

**Files:**
- Modify: `Sources/VibeLight/Resources/Web/panel.js`
- Modify: `Sources/VibeLight/Resources/Web/panel.css`
- Modify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`

- [ ] **Step 1: Replace the old row assertions with tests for the new full-width-title layout**

Update the existing result-row tests so they describe the approved shape: title on line one, model/token/time on the lower-left, path on the lower-right, and no context rail.

```swift
@Test("result rows show full-width title with bottom meta and path split")
func resultRowsShowFullWidthTitleWithBottomMetaAndPathSplit() throws {
    let context = try makePanelScriptContext()
    let payload = #"""
    [{
      "sessionId": "sess-1",
      "tool": "claude",
      "title": "Ship telemetry after preview header split and row retune",
      "project": "/Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation",
      "projectName": "vibelight",
      "gitBranch": "main",
      "status": "live",
      "startedAt": "2026-03-29T09:30:00Z",
      "tokenCount": 84800,
      "lastActivityAt": "2026-03-29T09:42:00Z",
      "activityStatus": "working",
      "relativeTime": "2m ago",
      "healthStatus": "ok",
      "healthDetail": "",
      "effectiveModel": "claude-sonnet-4",
      "contextUsedEstimate": 84800,
      "contextConfidence": "medium"
    }]
    """#

    _ = context.evaluateScript("window.updateResults(\(payload));")

    #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__title')", in: context) == "Ship telemetry after preview header split and row retune")
    #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 84.8k · 2m ago")
    #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__path')", in: context) == "/Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation")
    #expect(try invokeInt("__queryByClass(__els.results.children[0], 'row__context', false).length", in: context) == 0)
}

@Test("rows omit token number when confidence is too weak")
func rowsOmitTokenNumberWhenConfidenceIsTooWeak() throws {
    let context = try makePanelScriptContext()
    let payload = #"""
    [{
      "sessionId": "sess-2",
      "tool": "codex",
      "title": "Low confidence token count",
      "project": "/tmp/project",
      "projectName": "project",
      "gitBranch": "",
      "status": "live",
      "startedAt": "2026-03-29T09:30:00Z",
      "tokenCount": 61000,
      "lastActivityAt": "2026-03-29T09:42:00Z",
      "activityStatus": "waiting",
      "relativeTime": "2m ago",
      "healthStatus": "ok",
      "healthDetail": "",
      "effectiveModel": "gpt-5.2-codex",
      "contextUsedEstimate": 61000,
      "contextConfidence": "low"
    }]
    """#

    _ = context.evaluateScript("window.updateResults(\(payload));")

    #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "gpt-5.2-codex · 2m ago")
}
```

- [ ] **Step 2: Add one failing test proving the row chrome no longer renders dots**

```swift
@Test("working and waiting rows do not render status-dot ornaments")
func workingAndWaitingRowsDoNotRenderStatusDotOrnaments() throws {
    let context = try makePanelScriptContext()
    let payload = #"""
    [{
      "sessionId": "sess-working",
      "tool": "codex",
      "title": "Working row",
      "project": "/tmp/working",
      "projectName": "working",
      "gitBranch": "",
      "status": "live",
      "startedAt": "2026-03-29T09:30:00Z",
      "tokenCount": 5000,
      "lastActivityAt": "2026-03-29T09:42:00Z",
      "activityStatus": "working",
      "relativeTime": "2m ago",
      "healthStatus": "ok",
      "healthDetail": ""
    }, {
      "sessionId": "sess-waiting",
      "tool": "claude",
      "title": "Waiting row",
      "project": "/tmp/waiting",
      "projectName": "waiting",
      "gitBranch": "",
      "status": "live",
      "startedAt": "2026-03-29T09:30:00Z",
      "tokenCount": 5000,
      "lastActivityAt": "2026-03-29T09:42:00Z",
      "activityStatus": "waiting",
      "relativeTime": "2m ago",
      "healthStatus": "ok",
      "healthDetail": ""
    }]
    """#

    _ = context.evaluateScript("window.updateResults(\(payload));")

    #expect(try invokeInt("__queryByClass(__els.results, 'typing-dots', false).length", in: context) == 0)
    #expect(try invokeInt("__queryByClass(__els.results, 'status-dot', false).length", in: context) == 0)
}
```

- [ ] **Step 3: Run the JS test suite to confirm the old rail-based row still fails**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -100`

Expected: FAIL because the DOM still creates `.row__context`, `.typing-dots`, and top-row path placement.

- [ ] **Step 4: Rewrite the row DOM in `panel.js`**

Replace the old two-column/two-row plus context-rail layout with a simpler full-width title + bottom split row.

```javascript
function formatDisplayToken(result) {
  var used = asNumber(result.contextUsedEstimate);
  var confidence = ((result.contextConfidence || 'unknown') + '').toLowerCase();
  if ((confidence === 'high' || confidence === 'medium') && used !== null) {
    return formatCompactCount(used);
  }

  var tokenCount = asNumber(result.tokenCount);
  if (used === null && tokenCount !== null && tokenCount > 0) {
    return formatCompactCount(tokenCount);
  }

  return '';
}

function formatModelMeta(result) {
  var parts = [];
  var model = ((result.effectiveModel || '') + '').trim();
  if (model) {
    parts.push(model);
  } else {
    var toolFamily = ((result.tool || '') + '').trim().toLowerCase();
    parts.push(toolFamily ? (toolFamily + ' \u00B7 model unknown') : 'unknown model');
  }

  var displayToken = formatDisplayToken(result);
  if (displayToken) parts.push(displayToken);
  if (result.relativeTime) parts.push(result.relativeTime);
  return parts.join(' \u00B7 ');
}
```

Build the new bottom row:

```javascript
var metaRow = document.createElement('div');
metaRow.className = 'row__meta-row';

var modelMeta = document.createElement('span');
modelMeta.className = 'row__model-meta';
modelMeta.textContent = formatModelMeta(result);
metaRow.appendChild(modelMeta);

var path = document.createElement('span');
path.className = 'row__path';
path.textContent = formatSessionPath(result);
metaRow.appendChild(path);

body.appendChild(title);
body.appendChild(metaRow);
```

Do not append:

- `row__status-slot`
- `row__context`
- `createContextBlock(result)`
- `createStatusElement(result)`

- [ ] **Step 5: Flatten the row and preview styling in `panel.css`**

Adopt the approved structure and remove the old boxy preview cards.

```css
.row__body {
  flex: 1;
  min-width: 0;
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  grid-template-rows: auto auto;
  row-gap: 8px;
  align-items: center;
}

.row__meta-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  column-gap: 18px;
  align-items: center;
}

.row__path {
  justify-self: end;
  width: 320px;
  font-size: 12px;
  color: rgba(222,228,225,0.50);
  text-align: right;
}

.preview__state {
  color: rgba(222,228,225,0.72);
  font-size: 12px;
  font-weight: 600;
  margin-bottom: 5px;
}

.preview__detail {
  color: var(--label);
  font-size: 14px;
  line-height: 1.38;
  font-weight: 500;
  margin-bottom: 14px;
}

.preview__round {
  padding: 7px 0;
  border: 0;
  border-bottom: 1px solid rgba(255,255,255,0.03);
  background: transparent;
  border-radius: 0;
}
```

Remove or stop using:

- `.row__context*`
- `.status-dot*`
- `.typing-dot*`
- boxed/tinted `.preview__round--*` backgrounds

- [ ] **Step 6: Run the JS tests and a build**

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -100`

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/Resources/Web/panel.js Sources/VibeLight/Resources/Web/panel.css Tests/VibeLightTests/SearchPanelScriptTests.swift
git commit -m "feat: simplify panel rows and flatten preview styling"
```

---

## Task 4: Final Verification Pass

**Files:**
- Modify: none
- Verify: `Sources/VibeLight/Parsers/TranscriptTailReader.swift`
- Verify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Verify: `Sources/VibeLight/Resources/Web/panel.js`
- Verify: `Sources/VibeLight/Resources/Web/panel.css`
- Verify: `Tests/VibeLightTests/TranscriptTailReaderTests.swift`
- Verify: `Tests/VibeLightTests/SearchPanelControllerPreviewTests.swift`
- Verify: `Tests/VibeLightTests/SearchPanelScriptTests.swift`

- [ ] **Step 1: Run the three focused test targets**

Run: `swift test --filter TranscriptTailReaderTests 2>&1 | tail -60`

Run: `swift test --filter SearchPanelControllerPreviewTests 2>&1 | tail -60`

Run: `swift test --filter SearchPanelScriptTests 2>&1 | tail -100`

Expected: PASS.

- [ ] **Step 2: Run a full build**

Run: `swift build 2>&1 | tail -40`

Expected: PASS.

- [ ] **Step 3: Verify the final product behavior manually**

Check these behaviors in the running app:

- full title occupies the first row line
- path sits bottom-right and aligns across rows
- lower-left meta shows model + token + time when allowed
- rows show no rail and no rough percentage
- rows show no three-dot working ornament and no yellow waiting dot
- preview top shows state-only title and stronger detail line
- preview opens for already-selected rows after hover dwell
- finished Claude rows still open preview
- live Codex and live Claude preview states read correctly as `Question`, `Waiting`, `Working`, or `Error`
