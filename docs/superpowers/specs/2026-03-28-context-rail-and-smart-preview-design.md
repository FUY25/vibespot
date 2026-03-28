# VibeLight — Context Rail And Smart Preview Design

**Project:** `~/Desktop/project/vibelight`
**Date:** `2026-03-28`

## Problem

The current search panel is missing three pieces of high-value session context:

1. The results list does not show the active model.
2. The current token display is a rough lifetime approximation, not a useful estimate of current prompt occupancy.
3. The preview panel contains transcript tail data, but it does not answer the more important question: what is this session doing right now?

There is also a direct interaction problem:

4. Rows are keyboard-selectable and clickable, but not hover-selectable, which makes mouse-driven scanning feel broken.

## Goals

- Show the active model directly in the results pane.
- Show a visually prominent but compact context estimate using a long thin rail.
- Keep the context estimate honest: numeric only when confidence is acceptable, otherwise show unknown.
- Redesign preview behavior so it surfaces current state first, then only the minimum conversation context needed.
- Enable hover-based row selection without changing double-click-to-open behavior.

## Non-Goals

- This design does not add full raw terminal streaming to the preview.
- This design does not attempt a universal lifetime token usage number.
- This design does not surface health/error/model badges inside the preview body unless they are the most relevant current-state signal.

## Product Decisions

### Context Semantics

The context rail represents **latest active prompt occupancy**, not lifetime session size.

Rules:

- Count cached input toward occupancy.
- Do not count output tokens toward occupancy.
- Do not count reasoning tokens toward occupancy.
- After model changes, treat context as unknown until the next real assistant turn yields trustworthy usage.
- After compaction or reset-like behavior, the next usable sample becomes authoritative.

This is intentionally conservative. Unknown is better than a false number.

### Provider-Specific Estimation

#### Codex

Use the latest `event_msg.payload.type == "token_count"` sample from the session log.

- Numerator: `last_token_usage.input_tokens + last_token_usage.cached_input_tokens`
- Denominator: `model_context_window`
- Confidence: high when both fields are present

Do not use:

- `total_token_usage`
- `output_tokens`
- `reasoning_output_tokens`

#### Claude

Use the latest real assistant turn for the active model.

- Numerator: `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
- Denominator:
  - known `200K` for models whose active context window is unambiguous
  - known `1M` only when explicitly provable from model/mode evidence
  - otherwise unknown
- Confidence: medium at best, lower when model/window inference is weak

Claude-specific honesty rules:

- If the session has a model switch and no post-switch assistant turn yet, show unknown.
- If the capacity cannot be proven, show unknown.
- If server-side tool activity makes the number visibly noisy, prefer unknown over bluffing.

## Result Row Design

Each result row becomes a two-column, two-row card.

### Layout

Top row:

- Left: session title
- Right: fuller session path in muted gray text

Bottom row:

- Left: model name + relative time
- Right: long context rail + compact numeric suffix

Example shape:

```text
Refine preview behavior              /Users/fuyuming/Desktop/project/vibelight
Opus 4.6 · 12m ago                  [──────────────━━━━━━] 18% 41k
```

### Path Placement

The fuller path belongs on the right side of the card, not inside the title/meta column.

Reasoning:

- It answers “where is this session?” directly.
- It uses horizontal space that is currently underused.
- It keeps the left column focused on identity and recency.

Behavior:

- Muted gray
- Single-line
- Truncated intelligently when space is tight
- Prefer preserving the meaningful tail of the path over the leading home directory when possible

### Model Placement

The model name must be visible in the results pane, not only inside the preview.

Examples:

- `Opus 4.6 · 12m ago`
- `Sonnet 4.6 · running 3m`
- `GPT-5.2-Codex · 6m ago`

If the model is unknown, render:

- `Model unknown · 12m ago`

### Context Rail

The rail is the main visual signal. The text label is supportive and should stay compact.

Right-bottom hierarchy:

1. Long visible rail
2. Percent
3. Token count

Compact label rules:

- Show `18% 41k` when confidence is good
- Show `~18% 41k` when the number is usable but explicitly approximate
- Show `? 41k` when token usage exists but percent is not trustworthy
- Show `?` when the estimate is unknown

Do not show the word `tokens` in the row.

Visual behavior:

- Rail track should remain visible even at low fill
- Fill should be visibly longer and stronger than the current badge-like concept
- Color can warm as occupancy rises
- Rail should consume more width than the label text

## Preview Design

The preview should be structurally simple but behaviorally adaptive.

### Structure

1. Smart first line
2. Two rounds of exchange
3. Files changed / touched

The preview should not be a telemetry dashboard.

### Smart First Line

The first line answers: **what is this session doing right now?**

Priority order:

1. If waiting for input, show the pending question or user prompt needed.
2. If the latest meaningful state is an error, show the error summary.
3. If the session is actively doing work, show the current action.
4. Otherwise, show the distilled current task from the latest meaningful user ask.

Examples:

- `Waiting: Which layout do you prefer?`
- `Error: swift build failed in SearchPanelController.swift`
- `Editing panel.js`
- `Running swift build`
- `Current task: refine context rail and preview behavior`

### Two Rounds

The conversation area shows exactly two rounds when available, with the most recent round treated as the current task context.

Guidelines:

- Keep the text summarized and readable
- Strip obvious transcript noise
- Prefer meaningful user/assistant turns over raw tool chatter
- If space is tight, preserve the latest round over the older round

### Files

Show recent changed or touched files beneath the exchange block.

Rules:

- Prioritize edit-like file activity
- Show recent-first
- Keep the count small
- Use stronger visual emphasis than secondary transcript text

## Interaction Design

### Hover Selection

Mouse hover should move selection.

Rules:

- `mouseenter` selects the row
- hover alone does not activate the session
- click still selects
- double-click still opens
- keyboard navigation behavior remains unchanged

This makes the preview feel natural for mouse-driven scanning.

### Preview Dwell

Hover-selected rows continue to use dwell timing before preview opens.

Desired behavior:

- moving through rows updates selection immediately
- preview appears only after dwell
- selected live sessions can re-tail as their underlying transcript changes

This should feel live without becoming raw terminal streaming.

## Data Model Changes

Add indexed session fields for current-context telemetry and model identity:

- `effective_model`
- `context_window_tokens`
- `context_used_estimate`
- `context_percent_estimate`
- `context_confidence`
- `context_source`
- `last_context_sample_at`

These fields are for display and ranking only. They do not replace existing transcript indexing.

## Parser And Indexing Changes

### Codex

- Parse `turn_context.payload.model`
- Parse the latest token-count event
- Store latest usable `last_token_usage`
- Store `model_context_window`
- Prefer latest usable sample over lifetime totals

### Claude

- Parse assistant `message.model`
- Parse assistant usage fields:
  - `input_tokens`
  - `cache_read_input_tokens`
  - `cache_creation_input_tokens`
- Parse `/model` command output such as `Set model to Haiku 4.5`
- Invalidate context certainty after model changes until the next usable assistant turn
- Infer capacity conservatively

## Error Handling And Unknown States

Unknown is a first-class outcome, not a fallback bug.

Render unknown when:

- window size cannot be trusted
- model recently changed and has no trustworthy post-switch sample
- provider telemetry is incomplete
- parsing fails for the latest sample

UI behavior:

- row shows `?` instead of a misleading numeric percent
- rail stays neutral rather than pretending to have a fill level
- preview can still show current task and files even when context is unknown

## Visual Direction

The results pane should look cleaner and more structured, not denser.

Guidance:

- long, thin, visible context rail
- compact supportive labels
- muted right-side path column
- readable proportional text for preview content
- monospace only where file paths benefit from it
- stronger emphasis on files than on secondary conversation text
- larger preview width than the current one if needed for legibility

## Implementation Slices

### Slice 1

- Add model parsing and storage
- Add context telemetry parsing and storage
- Add honest unknown-state rules
- Redesign result rows:
  - two-column layout
  - right-side fuller path
  - model in left-bottom meta
  - long context rail with compact label
- Add hover-select behavior

### Slice 2

- Redesign preview structure and styling
- Add smart first-line logic
- Improve recent-round selection and summarization
- Improve file prioritization
- Add live refresh behavior for hovered live sessions where feasible

## Testing

Verify the following cases:

- Codex uses latest `last_token_usage`, not `total_token_usage`
- Cached tokens contribute to the context numerator
- Output and reasoning tokens do not affect the rail
- Claude model switch forces unknown until a usable post-switch assistant turn
- Claude ambiguous capacity renders unknown
- Known Claude capacities render numeric percent
- Hovering a row changes selection without activating it
- Dwell preview follows hover-selected rows
- Error sessions place the error summary in the first preview line
- Waiting-for-input sessions place the pending question in the first preview line

## Recommendation

Ship this in two slices.

Slice 1 gives immediate value with high-confidence model and context signals in the results pane plus the mouse interaction fix.

Slice 2 makes the preview feel smart instead of merely larger, while staying disciplined about not turning it into a noisy dashboard.
