# VibeLight — WKWebView UI Rewrite & Bug Fixes

**Date:** 2026-03-27
**Status:** Approved

## Problem Statement

VibeLight's AppKit-based UI has six issues:

1. **Sluggish navigation** — Arrow-key selection is slow because every selection change triggers `restoreSearchFieldFocus()` (async `makeFirstResponder`), `updateActionHint()` (new `ToolIcon.image()` allocation), and full animation rebuilds in `ResultRowView.configure()`.
2. **Liquid Glass conflict** — macOS Tahoe's Liquid Glass renders through `NSVisualEffectView(.popover)`, clashing with the Ethereal Terminal dark aesthetic defined in DESIGN.md.
3. **UI misalignment** — Nested `NSStackView` layout produces inconsistent spacing. Status labels float disconnected. Rows don't match the design mockup.
4. **Logos too small** — Tool icons are 22×22px; the design mockup shows ~32px.
5. **Duplicate Codex sessions** — Running `new` inside a Codex window creates a fresh session but the old one stays marked "live" because they share the same PID.
6. **CodexStateDB error spam** — `SQLITE_CANTOPEN` (error 14) floods logs when `~/.codex/state_5.sqlite` is missing or locked.

## Solution: WKWebView Panel

Replace the AppKit UI rendering layer with a WKWebView hosted inside the existing NSPanel. The native Swift shell (hotkey, window management, file watching, indexing, parsing, process detection) remains untouched.

### Why

DESIGN.md is a CSS spec — `rgba()` colors, `background-clip: text` shimmer, `repeating-linear-gradient` scanlines, `backdrop-filter` blur. AppKit approximates these with CALayer hacks. CSS expresses them directly.

### Architecture

```
┌─────────────────────────────────────────────┐
│ Native Swift Shell (unchanged)              │
│                                             │
│  main.swift          AppDelegate            │
│  HotkeyManager       WindowJumper           │
│  Indexer             IndexScanner           │
│  SessionIndex        Database               │
│  ClaudeParser        CodexParser            │
│  LiveSessionRegistry CodexStateDB           │
│  TerminalLauncher                           │
└────────────────┬────────────────────────────┘
                 │
        ┌────────▼────────┐
        │   WebBridge     │  WKScriptMessageHandler
        │  (new file)     │  Swift ↔ JS messaging
        └────────┬────────┘
                 │
┌────────────────▼────────────────────────────┐
│ Web UI Layer (new)                          │
│                                             │
│  panel.html — structure                     │
│  panel.css  — all DESIGN.md tokens          │
│  panel.js   — search, keyboard nav, render  │
└─────────────────────────────────────────────┘
```

### Communication Protocol

**Swift → JS** via `webView.evaluateJavaScript()`:
- `updateResults(json)` — push search results as JSON array
- `setTheme("dark"|"light")` — toggle color scheme
- `setGhostSuggestion(text)` — autocomplete hint
- `resetAndFocus()` — on panel show, clear + focus input

**JS → Swift** via `window.webkit.messageHandlers.bridge.postMessage()`:
- `{ type: "search", query: "..." }` — user typed (debounced 80ms in JS)
- `{ type: "select", sessionId: "..." }` — user pressed Enter
- `{ type: "escape" }` — dismiss panel
- `{ type: "resize", height: N }` — content height changed, Swift resizes NSPanel

**Key decision:** Arrow-key navigation stays 100% in JS. No Swift round-trip. CSS transitions handle visual feedback at 60fps.

### SearchPanelController Changes

The existing `SearchPanelController` is simplified:
- Remove: NSTableView setup, NSStackView layout, all AppKit view configuration
- Keep: NSPanel configuration, `show()`/`hide()`, screen positioning, deactivation observers
- Add: WKWebView setup, WebBridge instantiation
- The `refreshResults()` method now serializes results to JSON and calls `evaluateJavaScript("updateResults(...)")` instead of `reloadData()`

### WKWebView Transparency

```swift
webView.isOpaque = false
webView.setValue(false, forKey: "drawsBackground")
panel.backgroundColor = .clear
```

The CSS `backdrop-filter: blur(48px) saturate(200%)` on the panel div provides the frosted glass effect, fully bypassing Liquid Glass.

## CSS Design Tokens

All DESIGN.md values map to CSS custom properties:

### Colors (Dark Mode)

```css
:root {
  --bg: #08090A;
  --surface: #111314;
  --surface-card: #161819;
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
  --label: #DEE4E1;
  --label-secondary: rgba(222,228,225,0.5);
  --label-tertiary: rgba(222,228,225,0.22);
  --separator: rgba(255,255,255,0.04);
  --selection: rgba(170,255,220,0.06);
  --selection-edge: rgba(170,255,220,0.08);
  --ghost: rgba(170,255,220,0.04);
  --kicker: #AAFFDC;
}
```

### Colors (Light Mode)

```css
@media (prefers-color-scheme: light) {
  :root {
    --bg: #F4F7F6;
    --surface: #E8EDEB;
    --surface-card: #FFFFFF;
    --neon-dim: #00E1AB;
    --label: #151917;
    --label-secondary: #3A4A43;
    --label-tertiary: rgba(58,74,67,0.35);
    --separator: rgba(58,74,67,0.06);
    --selection: rgba(0,225,171,0.06);
    --selection-edge: rgba(0,225,171,0.12);
    --ghost: rgba(185,203,193,0.12);
    --kicker: #006B54;
  }
}
```

### Typography

```css
--font-title: 'JetBrains Mono', monospace;  /* 500 14px, -0.01em */
--font-ui: -apple-system, 'SF Pro', system-ui;  /* search, metadata */
--font-activity: 'JetBrains Mono', monospace;  /* 400 11.5px */
--font-status: 'JetBrains Mono', monospace;  /* 500 10px, 0.1em spacing, uppercase */
--font-hint: 'JetBrains Mono', monospace;  /* 400 11px */
```

JetBrains Mono bundled as a web font in the app's Resources.

### Spacing

```css
--panel-width: 720px;
--panel-radius: 12px;
--row-radius: 6px;
--row-h-closed: 56px;
--row-h-active: 74px;
--row-v-pad: 10px;
--row-h-pad: 14px;
--icon-size: 32px;  /* bumped from 22px */
--icon-radius: 5px;
--logo-gap: 12px;
--search-height: 64px;
--search-h-pad: 22px;
--search-top-pad: 14px;
--results-h-pad: 6px;
--results-bottom-pad: 12px;
--max-visible-rows: 7;
```

### Panel Appearance

```css
.panel {
  background: rgba(17,19,20,0.82);
  backdrop-filter: blur(48px) saturate(200%);
  border: 1px solid var(--ghost);
  border-radius: var(--panel-radius);
  box-shadow: 0 0 120px rgba(170,255,220,0.04),
              0 0 40px rgba(170,255,220,0.02),
              0 32px 80px rgba(0,0,0,0.5);
}

.panel__top-edge {
  /* gradient line across top */
  background: linear-gradient(90deg, transparent 15%, var(--neon-glow-strong) 50%, transparent 85%);
  height: 1px;
}

.panel__scanlines {
  /* CRT texture */
  background: repeating-linear-gradient(0deg, transparent, transparent 1px, rgba(0,0,0,0.008) 1px, rgba(0,0,0,0.008) 2px);
  pointer-events: none;
}
```

## CSS Animations

### Shimmer (working sessions)

```css
.row--working .row__title {
  background: linear-gradient(90deg, var(--label) 0%, var(--neon) 50%, var(--label) 100%);
  background-size: 200%;
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  animation: shimmer 2.5s linear infinite;
}

@keyframes shimmer {
  from { background-position: 100% 0; }
  to { background-position: -100% 0; }
}
```

### Breathing (awaiting input)

```css
.row--waiting .row__status-text {
  color: var(--waiting-amber);
  animation: breathe 3s ease-in-out infinite alternate;
}

@keyframes breathe {
  from { opacity: 0.4; }
  to { opacity: 0.9; }
}
```

### Typing Dots (working indicator)

```css
.typing-dot {
  width: 3.5px; height: 3.5px;
  border-radius: 50%;
  background: var(--neon-dim);
  animation: bounce 1.4s infinite;
}
.typing-dot:nth-child(2) { animation-delay: 0.2s; }
.typing-dot:nth-child(3) { animation-delay: 0.4s; }

@keyframes bounce {
  0%, 60%, 100% { transform: translateY(0); }
  30% { transform: translateY(-3px); }
}
```

### Status Dot Pulse

```css
.status-dot {
  width: 6px; height: 6px;
  border-radius: 50%;
  animation: pulse 2s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { transform: scale(1); opacity: 0.6; }
  50% { transform: scale(1.2); opacity: 1; }
}
```

## HTML Structure

```html
<div class="panel">
  <div class="panel__top-edge"></div>
  <div class="panel__scanlines"></div>

  <div class="search-bar">
    <svg class="search-icon"><!-- magnifying glass --></svg>
    <input class="search-input" placeholder="Search sessions" />
    <span class="action-hint"></span>
    <img class="search-bar__tool-icon" />
  </div>

  <div class="separator"></div>

  <div class="results" id="results">
    <!-- Rendered by JS -->
    <div class="row row--selected row--working">
      <img class="row__icon" src="claude-icon.png" />
      <div class="row__body">
        <div class="row__header">
          <span class="row__title">Fix hotkey reliability</span>
          <div class="row__status">
            <span class="status-dot status-dot--green"></span>
            <div class="typing-dots">
              <span class="typing-dot"></span>
              <span class="typing-dot"></span>
              <span class="typing-dot"></span>
            </div>
          </div>
        </div>
        <span class="row__meta">2m ago · vibelight / fix-hotkey · 8.2k tokens</span>
        <span class="row__activity row__activity--tool">Edit Sources/VibeLight/HotkeyManager.swift:42-97</span>
      </div>
    </div>
  </div>
</div>
```

## Row States

### Working

- Title: shimmer animation
- Status: green pulsing dot + typing dots
- Activity: cyan monospace text (`row__activity--tool`)
- Full opacity

### Awaiting Input

- Title: full opacity, no animation
- Status: amber breathing "AWAITING" + amber pulsing dot
- Activity: italic system font, 55% opacity (`row__activity--assistant`)

### Closed

- Title: 35% opacity
- No status indicator, no activity line
- Metadata at normal secondary opacity

### Action (New Session)

- Title: neon green color with text-shadow glow
- Tool logo icon
- Metadata shows target project directory

## JS Responsibilities

### Keyboard Navigation

```javascript
document.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowDown') { moveSelection(1); e.preventDefault(); }
  if (e.key === 'ArrowUp') { moveSelection(-1); e.preventDefault(); }
  if (e.key === 'Enter') { activateSelected(); }
  if (e.key === 'Escape') { bridge.postMessage({ type: 'escape' }); }
  if (e.key === 'Tab') { acceptGhostOrDrillHistory(); e.preventDefault(); }
});
```

All navigation is DOM-only — add/remove `.row--selected` class, `scrollIntoView()`. No Swift round-trip.

### Result Rendering

On receiving `updateResults(json)`:
1. Diff against current results by `sessionId`
2. Update changed rows in-place (update text, toggle state classes)
3. Add new rows, remove stale rows
4. Preserve selection index when possible
5. Post `{ type: "resize", height }` if content height changed

### Search Input

```javascript
const input = document.querySelector('.search-input');
let debounceTimer;
input.addEventListener('input', () => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    bridge.postMessage({ type: 'search', query: input.value });
  }, 80);
});
```

## Bug Fix: Duplicate Codex Sessions

**Root cause:** When `new` is run inside a Codex window, a fresh session is created but the old session retains the same PID. `LiveSessionRegistry` sees the process alive and marks both as "live".

**Fix in `Indexer.refreshLiveSessions()`:**

After collecting alive sessions, group by PID. When multiple sessions share a PID, only the most recently started session stays "live" — others are marked "closed".

This requires either:
- `LiveSessionRegistry.scan()` returning session start times, or
- Looking up `startedAt` from `SessionIndex` for each alive session

The simpler approach: after marking all alive sessions as "live" and stale ones as "closed" (existing logic), add a second pass that queries `SessionIndex` for sessions sharing a PID and closes all but the newest.

## Bug Fix: CodexStateDB Error Spam

**Root cause:** `~/.codex/state_5.sqlite` doesn't exist or is locked by another process. The `fileExists` guard passes but `sqlite3_open_v2` fails (TOCTOU race), or the file genuinely doesn't exist.

**Fixes:**

1. **Cache negative lookups:** Add a class-level timestamp tracking the last failed open attempt. If less than 30 seconds have elapsed, return empty immediately without retrying.

2. **Throttle log output:** Track the last log timestamp. Only print the error message if 60+ seconds have passed since the last log, preventing log flooding.

3. **CodexStateDB is optional enrichment:** `gitBranchMap()` already returns `[:]` on failure. The callers handle this gracefully. The only change needed is reducing noise.

## File Changes Summary

### New Files
- `Sources/VibeLight/UI/WebBridge.swift` — WKScriptMessageHandler, Swift↔JS bridge
- `Sources/VibeLight/Resources/Web/panel.html` — panel structure
- `Sources/VibeLight/Resources/Web/panel.css` — all design tokens + animations
- `Sources/VibeLight/Resources/Web/panel.js` — search, navigation, rendering

### Modified Files
- `SearchPanelController.swift` — replace AppKit views with WKWebView host
- `Indexer.swift` — add PID-based dedup in `refreshLiveSessions()`
- `CodexStateDB.swift` — add failure caching and log throttling
- `LiveSessionRegistry.swift` — minor: support PID grouping lookup

### Deleted Files
- `ResultRowView.swift` — replaced by HTML/CSS rows
- `ResultsTableView.swift` — replaced by HTML/CSS results container
- `DesignTokens.swift` — replaced by CSS custom properties
- `SearchField.swift` — replaced by HTML input element
- `ToolIcon.swift` — replaced by `<img>` tags with bundled PNGs

### Unchanged Files
- `main.swift`, `AppDelegate.swift`, `HotkeyManager.swift`
- `Indexer.swift` (data logic), `IndexScanner.swift`
- `SessionIndex.swift`, `Database.swift`
- `ClaudeParser.swift`, `CodexParser.swift`, `Models.swift`
- `WindowJumper.swift`, `TerminalLauncher.swift`
- `FileWatcher.swift`, `Debouncer.swift`
- `RelativeTimeFormatter.swift`, `ActivityPreview.swift`
- All test files (tests may need updates for deleted UI classes)
