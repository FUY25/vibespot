# Preferences Redesign And Source Fallback

**Date:** 2026-04-18  
**Status:** Design approved, pending implementation  
**Approval note:** The default VibeLight design system is explicitly overridden for this window. The user approved a quieter, more Notion-like preferences treatment for `Settings` and `About`.

## Problem

The current preferences window has two classes of issues:

1. **Broken behavior**
   - Shortcut capture can get stuck because the sheet lifecycle is fragile.
   - Buttons do not always dismiss or return the user to a clean state.
2. **Weak information architecture**
   - The window does not yet expose `Search history` even though the runtime already supports live-only vs history mode.
   - Session source locations are hardcoded to home-relative Claude/Codex directories, so users have no recovery path if auto-detection fails.
3. **Visual noise**
   - The preferences layout reads more like a temporary control surface than a calm configuration window.
   - Row alignment, content widths, and section spacing are not disciplined enough.

## Approved Direction

### 1. Window Structure

Keep exactly **two tabs**:

- `Settings`
- `About`

No third tab, no search rail, no diagnostics/debug tab.

### 2. Visual Direction

The preferences window should move toward **editorial minimalism with a Notion-like tone**, but without becoming soft or bubbly.

Approved visual rules:

- Typography is **smaller** than the current mock and smaller than the previous large-header treatment.
- Corners are **less rounded** than the current implementation.
- Spacing is **tight and intentional**, not airy.
- Group settings into **subtle sections**, not large hero cards.
- Remove the `"Main Settings"` style hero phrasing. The pane title should stay simple.
- Surfaces are flatter and quieter than the rest of VibeLight.
- Alignment is a first-class requirement: the redesign is not complete unless rows, labels, controls, and section widths line up cleanly.

### 3. Alignment Requirements

The implementation must treat alignment as acceptance criteria, not polish:

- Sidebar width is fixed and visually subordinate to the content column.
- The content column has one stable readable width rather than ad hoc card widths.
- Every settings row uses the same two-column structure: label block on the left, control block on the right.
- Control-leading edges align across rows.
- Section headings, row text, helper text, and status copy all share a consistent left edge.
- Vertical spacing uses a narrow scale and does not drift row to row.
- There should be no oversized header stack, no uneven button group placement, and no mismatched row baselines.

## Settings Tab Scope

The `Settings` tab should remain small and repeatedly useful.

Approved rows:

1. `Launch at login`
2. `Appearance`
3. `Shortcut`
4. `Search history`
   - Toggle label should communicate whether historical sessions are included in search.
   - Add a small footnote that users can still switch modes from the search panel with `Tab` after searching.
5. `Data Sources`
   - Claude root status
   - Codex root status
   - fallback custom root selection behavior
6. `Reindex`
7. `Export diagnostics`

## About Tab Scope

The `About` tab should stay quiet and read-only.

Approved content:

1. App name
2. Version/build
3. Shortcut summary
4. Launch-at-login support summary
5. Data-source status summary

No marketing copy, no setup wizard language, no large decorative hero.

## Data Source Behavior

The app should support **auto-detect first, fallback override second**.

### Source Model

Do **not** ask users to choose individual JSON files.

Instead, configure **root folders**:

- Claude root: equivalent to `~/.claude`
- Codex root: equivalent to `~/.codex`

Derived paths come from those roots:

- Claude projects path
- Claude live session PID path
- Codex sessions path
- Codex session index path
- Codex state database path

### UX Rules

1. Default mode is `Auto`.
2. If auto-detect succeeds:
   - Show the detected root and `Auto` status.
   - Do not force the picker UI open.
   - Offer a quiet way to switch to a custom root if the user wants it.
3. If auto-detect fails:
   - Surface that failure in `Data Sources`.
   - Make the custom directory picker easy to reach.
4. If the user switches to `Custom`:
   - open a directory-only picker
   - save the selected root
   - validate the expected child paths derived from that root
   - allow resetting back to `Auto`

### Validation Rules

- Claude custom root is valid when the chosen root exists and yields usable Claude child paths.
- Codex custom root is valid when the chosen root exists and yields usable Codex child paths.
- Invalid custom roots should not silently replace working configuration.
- The UI should explain the problem in compact status copy, not in a modal-heavy flow.

## Architecture

### Settings Model

Extend `AppSettings` with per-tool source preferences:

- mode: `auto` or `custom`
- custom root path

`historyMode` stays in settings and is simply surfaced in the UI.

### Source Resolution

Introduce a single resolver/locator that:

- derives real Claude/Codex paths from settings
- reports current status for the UI
- decides whether manual override controls should be emphasized

### Runtime Consumers

Every runtime path consumer must use resolved source paths instead of hardcoded home-relative paths:

- `Indexer`
- `IndexScanner`
- `IndexingHelpers`
- `LiveSessionRegistry`
- `SearchPanelController`
- `CodexStateDB`

### Source Change Handling

Changing source roots is not just a UI update.

When source settings change:

1. Persist settings.
2. Rebuild the effective source-path resolution.
3. Clear stale indexed session data tied to the old roots.
4. Restart or reconfigure runtime consumers to watch and index the new roots.

Without a rebuild step, old sessions can remain in SQLite and contaminate results.

## Testing Requirements

Minimum coverage:

1. Settings persistence for custom source preferences.
2. Source resolution logic for:
   - successful auto-detect
   - missing auto roots
   - valid custom roots
   - invalid custom roots
3. Preferences controller behavior for:
   - shortcut sheet cancel/close
   - tab switching
   - search history toggle save/apply
   - custom source controls appearing when needed
4. Runtime integration for custom root usage in file lookup and indexing.

## Acceptance Criteria

The work is complete when all of the following are true:

1. Every preferences button works and every modal/sheet can be exited cleanly.
2. `Settings` and `About` are the only tabs.
3. The layout is visually tighter, flatter, and more disciplined than the current preferences window.
4. The layout is **aligned**:
   - rows line up
   - controls line up
   - sections line up
   - spacing is consistent
5. `Search history` is user-configurable from preferences.
6. Auto-detect remains the default for Claude/Codex roots.
7. Manual root selection works as a fallback when auto-detect fails, and users can deliberately switch to custom roots if needed.
8. Switching source roots does not leave stale old-root sessions in the indexed result set.
