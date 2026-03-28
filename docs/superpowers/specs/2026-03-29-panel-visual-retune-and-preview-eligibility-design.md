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
- token count may appear inline with model and time when available
- keep monospace styling if it matches the surrounding row language
- avoid surfacing extra health or badge clutter here

Examples:

- `gpt-5.2-codex · 84k · 2m ago`
- `claude-sonnet-4-6 · 146k · 4d ago`
- `model unknown · 9m ago`

### Row Structure Override

The approved row structure for this update is simpler than the earlier rail-based design.

Rules:

- title gets the full top line
- the second line is split left/right
- lower-left shows model, token count when available, and relative time
- lower-right shows the fuller path
- omit the token count entirely when it is unavailable or not trustworthy enough to show cleanly

Approved shape:

```text
Fix live Codex session resolution after rollout path remap and title refresh
gpt-5.2-codex · 84k · 2m ago          /Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation
```

This overrides the rail display for the current slice. The context rail and rough percentage are deferred to a later update.

### Token Count Rules

Approved rendering rules:

- show only the compact token count, not the rough percentage
- do not show `?`
- do not show a rough estimate badge
- if the number is too uncertain to show cleanly, omit it

Examples:

- `84k`
- `146k`

This preserves usefulness while staying honest while freeing more space for the title and path.

### Alignment Requirement

The lower-left meta block and lower-right path block must use a stable second-line layout.

Implementation consequence:

- do not let each row size its bottom-right path independently
- use a stable bottom-row split so the path aligns cleanly across rows

This is an explicit design requirement, not a polish detail.

### Status Indicators

The result rows should not use separate status-dot ornaments for this design.

Rules:

- remove the animated three-dot working indicator from the row chrome
- remove the yellow waiting dot from the row chrome
- rely on the row’s typography, motion treatment, and preview state header instead of standalone dots

This keeps the rows quieter and avoids low-value decorative status clutter.

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

- title line carries only the state
- detail line carries the concrete explanation
- the detail line must not read like a footnote
- the detail line should be at least as visible as the user or assistant summary rows
- the title line may be quieter than the detail line if that produces better hierarchy

Examples:

- `Question`
  - `Should ambiguous sessions stay rail-only until a new assistant turn provides trustworthy usage data?`
- `Error`
  - `SearchPanelController.swift is missing a valid preview width update after hover-open.`
- `Working`
  - `Refining transcript hierarchy and file list emphasis in the search panel preview.`
- `Waiting`
  - `Need user input before choosing the next implementation slice.`

This keeps the top coherent and removes the layered feeling from the current preview.
The actual question, error explanation, or work summary should feel like the main content of the preview top, not like subdued metadata.

### State Detection

The preview title state must be correct for both Codex and Claude.

Rules:

- state detection is provider-neutral at the UI layer
- the same visible states should be used for Codex and Claude:
  - `Question`
  - `Waiting`
  - `Working`
  - `Error`
  - fallback neutral state when none of the above is justified
- do not infer `Working` merely from live-ness
- do not infer `Waiting` from styling artifacts such as a green or amber row treatment alone
- prefer transcript and activity evidence over superficial row status text

Desired behavior:

- if the latest meaningful content is a user-facing ask awaiting input, use `Question` or `Waiting`
- if the session is actively performing work, use `Working`
- if the latest meaningful content is a failure, use `Error`
- the same logic must behave correctly for live Codex sessions and live Claude sessions

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
- if the token number is not trustworthy, suppress the number
- do not visually overstate low-confidence data

This is the approved product tone for uncertainty.

## Implementation Notes

Expected affected areas:

- `Sources/VibeLight/Resources/Web/panel.css`
- `Sources/VibeLight/Resources/Web/panel.js`
- `Sources/VibeLight/UI/SearchPanelController.swift`
- preview-related tests and panel script tests

Expected implementation themes:

- full-width title with second-line meta/path split
- compact token count instead of rail/percentage
- removal of row status dots
- preview top simplification from three layers to two
- compact file list styling
- panel width expansion fix
- preview-open eligibility fix for finished rows
- provider-correct state derivation for Codex and Claude preview headers

## Testing

Verify the following:

- title gets the full first line
- lower-left meta and lower-right path align across mixed rows
- token count appears only when it is trustworthy enough to show cleanly
- rows show no `?`
- rows show no rail and no rough percentage
- result rows show no three-dot working indicator and no yellow waiting dot
- preview top renders exactly two layers: title and detail
- preview title is state-only, such as `Question`, `Working`, `Waiting`, or `Error`
- preview state detection is correct for both Codex and Claude
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
