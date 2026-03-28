# VibeLight — Panel Visual Retune And Preview Eligibility Design

**Project:** `~/Desktop/project/vibelight`
**Date:** `2026-03-29`
**Status:** Approved in interactive design review

## Purpose

This spec refines the March 28 context-rail and smart-preview design into the exact visual and behavioral shape approved in review.

It does four things:

1. Retunes the search results row so the path is more visible and the context rail feels premium instead of loud.
2. Simplifies the preview pane into a cleaner split-transcript layout with better hierarchy.
3. Makes low-confidence context honest without showing `?` in the product UI.
4. Fixes preview eligibility so finished sessions still open preview normally.

This spec narrows and overrides the relevant visual details from:

- `docs/superpowers/specs/2026-03-28-context-rail-and-smart-preview-design.md`

It does not replace the underlying telemetry and parsing direction from that document.

## Problems

The current panel still has several product-level issues:

1. The right-side path is too small and too faint to be useful as quick scan data.
2. The context rail is visually noisy in the wrong places:
   - the fill is too bright
   - the numeric text competes too much with the rest of the row
   - rails do not align cleanly from row to row
3. The preview pane still feels over-designed:
   - too many visual layers near the top
   - transcript chunks can feel boxed rather than editorial
   - changed files can visually overpower the main reading flow
4. Some rows do not open preview at all when they should, including finished sessions whose visible title ends in trivial text such as `Done`.
5. The native panel width can fail to fully accommodate the preview pane, which causes clipping.

## Goals

- Make the results pane scan faster by strengthening the path and calming the context display.
- Keep the context rail as the primary occupancy signal, with numeric text always secondary.
- Remove `?` from the UI. Uncertain states should be understated, not noisy.
- Make the preview feel editorial and useful:
  - one clear top line
  - one detail line
  - two rounds of exchange
  - small file list
- Ensure any real session row can open preview, even if the row looks finished.
- Expand the native panel enough that the preview column is fully visible.

## Non-Goals

- This spec does not introduce raw streaming terminal output into preview.
- This spec does not add more preview telemetry sections.
- This spec does not attempt to force numeric context estimates when confidence is weak.
- This spec does not change the earlier plan for provider-specific telemetry parsing, except where honesty rules affect rendering.

## Result Row Design

### Layout

Each row remains a two-row composition, but the right side becomes a fixed visual column so path and context align across rows.

Top row:

- Left: session title
- Right: full session path, visually stronger than before

Bottom row:

- Left: model name and relative time
- Right: context rail and numeric suffix

Approved shape:

```text
Fix live Codex session resolution     /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
gpt-5.2-codex · 2m ago                [───────────────] ~18% · 84k
```

### Path

The path remains on the right side of the row and uses a single line.

Rules:

- visibly larger than the current implementation
- muted gray, but not ghosted out
- right-aligned
- ellipsized when needed
- the right column width should be stable so the rows align cleanly

Reasoning:

- the path answers “where is this session?” immediately
- the right side has enough horizontal space to carry this information
- strengthening the path improves orientation without making the row noisy

### Model And Time

Model stays in the results pane and remains high-value scan data.

Rules:

- render model and time together on the lower-left
- keep monospace styling if it matches the surrounding row language
- avoid surfacing extra health or badge clutter here

Examples:

- `gpt-5.2-codex · 2m ago`
- `claude-sonnet-4-6 · 4d ago`
- `model unknown · 9m ago`

### Context Rail

The rail is the primary context signal. Text is supportive only.

Rules:

- rail sits on the lower-right
- numeric text sits to the right of the rail, not before it
- rail should be slightly thicker than the current implementation
- rail should be optically centered on the row line
- rail total length stays long and visually meaningful
- fill color should be muted, not neon-bright

The approved visual intent is:

- long muted track
- restrained sage/gray-green fill
- compact, quiet numeric text on the far right

### Context Text Rules

The product should avoid fake precision and should not display `?`.

Approved rendering rules:

- when numeric context is shown, use the same understated style regardless of whether confidence is high or medium
- numeric text stays secondary to the rail
- use approximate presentation for displayed numbers
- place percentage and token count together on the right

Examples:

- `~18% · 84k`
- `~34% · 146k`

Low-confidence rules:

- do not show `?`
- if confidence is too weak for numeric text, keep the rail and suppress the number
- an understated `estimate` label is acceptable if needed, but rail-only is preferred when it reads cleaner

This preserves usefulness while staying honest.

### Alignment Requirement

The right-side path row and right-side context row must share the same column width.

Implementation consequence:

- do not let each row size its right side independently
- use a stable column width or equivalent layout constraint so rails line up across rows

This is an explicit design requirement, not a polish detail.

## Preview Design

### Overall Direction

The preview should feel simple and premium.

It should not use:

- message boxes
- tinted message cards
- decorative sub-panels
- layered hero treatments

It should use:

- typography
- spacing
- thin separators
- subtle role color

### Top Section

The preview top must have exactly two layers:

1. one title line
2. one detail line

No extra kicker, badge, or header layer above the title.

Approved behavior:

- title line carries the state and subject together
- detail line carries the concrete explanation

Examples:

- `Question: Claude context estimate policy`
  - `Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?`
- `Error: swift build failed`
  - `SearchPanelController.swift is missing a valid preview width update after hover-open.`
- `Working: redesign preview layout`
  - `Refining transcript hierarchy and file list emphasis in the search panel preview.`

This keeps the top coherent and removes the layered feeling from the current preview.

### Transcript Area

The preview transcript uses a split layout, not boxes.

Rules:

- show two rounds of exchange when available
- use a small left role column and a larger right text column
- `User` and `Assistant` may differ slightly in text color
- keep the transcript readable, not decorative
- preserve the most recent round when space is tight

The transcript should read like a compact editorial digest, not a dumped log.

### Files Changed

Files changed stays in the preview, but must be quieter and smaller than the current mockup that felt oversized.

Rules:

- keep file rows compact
- show file name first
- show directory as subdued secondary text
- maintain a small list, recent first
- do not let the files block visually dominate the preview

This section supports orientation, but it is secondary to the title and transcript.

## Preview Eligibility

Preview-open behavior is a separate correctness issue from preview content selection.

### Rule

Any real session row should be previewable.

Exceptions:

- action / launch rows

Non-exceptions:

- live sessions
- waiting sessions
- closed sessions
- finished sessions
- rows whose visible title or tail contains trivial completion text such as `Done`

### Requirement

A finished Claude session like the one shown in review must still open preview on dwell/selection.

The presence of trivial completion text must not suppress preview opening.

This bug is about whether preview opens at all, not about what content the preview would show after opening.

## Preview Content Prioritization

Once preview opens, the title/detail extraction should remain content-smart, but that is secondary to eligibility.

Rules:

- trivial status tails such as `Done` are not considered meaningful content
- preview extraction should fall back to the last meaningful question, error, task, or answer summary

This rule matters only after preview is already allowed to open.

## Sizing

The native panel must expand enough to fit the preview column without clipping.

Requirement:

- panel expansion width should be sized from the actual preview width, not a smaller legacy constant

Product result:

- the right preview column should feel like a real second pane
- no cropped right edge
- no partially hidden transcript area

## Interaction Rules

### Hover Selection

Existing agreed rule remains:

- moving the mouse onto a real session row selects it
- dwell opens preview
- hover does not activate the session
- click selects
- double-click opens

### Mouse Scanning

The combined effect should make the panel feel natural for quick mouse scanning:

- selection follows the pointer
- preview opens reliably for any session row
- preview does not disappear merely because the session is finished

## Rendering Honesty

The UI should prefer omission over bluffing.

Rules:

- no `?` marker in the product
- if the number is not trustworthy, suppress the number
- keep the rail as the lightweight estimate signal when possible
- do not visually overstate low-confidence data

This is the approved product tone for uncertainty.

## Implementation Notes

Expected affected areas:

- `Sources/VibeLight/Resources/Web/panel.css`
- `Sources/VibeLight/Resources/Web/panel.js`
- `Sources/VibeLight/UI/SearchPanelController.swift`
- preview-related tests and panel script tests

Expected implementation themes:

- stable right-column sizing for row path and context
- muted rail retune
- preview top simplification from three layers to two
- compact file list styling
- panel width expansion fix
- preview-open eligibility fix for finished rows

## Testing

Verify the following:

- paths and rails align across mixed rows
- the rail is thicker and remains vertically centered
- numeric context appears to the right of the rail
- low-confidence rows show no `?`
- low-confidence rows can render rail-only cleanly
- preview top renders exactly two layers: title and detail
- transcript uses separators, not boxed message cards
- files changed remains compact and visually secondary
- preview pane is fully visible with no clipping
- a finished session row still opens preview on dwell
- action rows still do not open preview

## Recommendation

Implement this as a focused UI correctness pass on top of the existing context-rail and smart-preview work.

The key product principle is:

- stronger structure
- less decoration
- honest uncertainty
- preview reliability for every real session
