# Flare — Public Beta Readiness Design

**Date:** 2026-03-30  
**Product:** Flare (macOS menu bar app)  
**Goal:** Make Flare ready for invite-only public beta in 1 week for heavy Codex + Claude CLI users.

## 1. Product Goal And Scope

Flare already has strong core session indexing/search behavior. To feel like a real product for external users, the missing layer is first-run usability, basic preferences, supportability, and distribution discipline.

This design defines a 1-week beta scope that prioritizes one reliable core flow:

`install -> first launch onboarding -> find/resume/start session reliably`

### In Scope

1. Two-screen onboarding flow.
2. One-page preferences window.
3. Basic product branding consistency.
4. Beta distribution path (direct download first, Homebrew cask after release).
5. Reliability gates for core session workflows.

### Out Of Scope (Deferred)

1. Multi-provider-first UX (beyond Codex + Claude focus).
2. Advanced analytics/telemetry dashboards.
3. Deep onboarding personalization.
4. Full auto-update framework (Sparkle-level).

## 2. Target User And Beta Mode

### Target User (Day 1)

Heavy Codex + Claude CLI users.

### Beta Mode

Invite-only technical beta (before code-signing/notarization is available).

### UX Success Criteria

1. New user reaches a successful first action in under 3 minutes.
2. Codex-only users can complete setup without Claude being installed.
3. Bug reports can include exported diagnostics bundle.
4. No blocker in the launcher flow for `new codex` / `new claude` and resume/jump behavior.

## 3. Onboarding Design (2 Screens)

Onboarding is intentionally short and linear.

### Screen A: Welcome + Product Intro

Purpose: establish value and trust quickly.

Content:
1. Headline: Flare intro.
2. 3 concise product value bullets:
   - unified live + history session search
   - instant resume / jump / new-session launch
   - smart preview for session state
3. Privacy statement:
   - local-first behavior
   - no cloud upload by default
4. Primary CTA: `Continue Setup`.

### Screen B: Setup Test

Purpose: make setup status explicit and fixable.

Checks:
1. CLI availability (`codex`, `claude`) with pass/fail state.
2. Required path accessibility for session discovery.
3. Recheck action for all tests.

Controls:
1. Hotkey field:
   - show default primary hotkey (`Cmd+Shift+Space`)
   - allow user to set their own hotkey before finishing onboarding
2. Launch-at-login toggle:
   - default: ON for new users
3. Permission help if required paths are not accessible.

Completion:
1. If checks pass (or acceptable partial pass, such as Codex present and Claude missing), user can finish.
2. Clear completion CTA: `Start Using Flare`.

### Error Handling In Onboarding

1. Missing tool binary:
   - show clear non-blocking status and install hint.
2. Path/permission failure:
   - show exact path and quick recheck path.
3. Hotkey conflict:
   - prevent save and show direct conflict message.
4. Launch-at-login failure:
   - keep onboarding completable, show warning.

## 4. Preferences Design (Single Page)

One-page preferences only. No tabbed complexity for this beta.

Sections:
1. General:
   - hotkey editor
   - theme mode
   - launch at login toggle
2. Search:
   - history mode/default behavior
3. Data:
   - `Reindex Now` action
4. Support:
   - `Export Diagnostics` action
   - version/build display

Explicit exclusion:
1. No ranking toggles in this beta.

## 5. Architecture And Data Flow

### New/Updated Components

1. `OnboardingController`
   - owns two-screen onboarding state machine.
2. `PreferencesController` (single-page)
   - reads/writes typed settings.
3. `SettingsStore`
   - single source of truth for:
     - hotkey
     - theme
     - history mode
     - launch-at-login
     - onboarding-complete flag
4. `EnvironmentCheckService`
   - runs tool/path checks and returns structured results.
   - never assumes a hardcoded project path; paths are discovered from runtime environment and user-granted locations.
5. `DiagnosticsExporter`
   - packages useful local diagnostics into a user-shareable archive.

### Launch Lifecycle

1. App starts.
2. If onboarding is incomplete -> show onboarding.
3. On onboarding complete -> persist settings -> open normal Flare workflow.
4. Preferences changes apply immediately when safe; otherwise require relaunch only for impacted setting.

## 6. Distribution And Release Path

### Primary (Day 1)

Direct downloadable release artifact with install instructions.

### Secondary (Soon After)

Homebrew cask publish path.

### Required Release Assets

1. Versioned artifact.
2. Release notes with known limitations.
3. Install doc including first-run behavior and troubleshooting.
4. Rollback procedure for broken beta release.

## 7. Reliability Gates (Beta Blockers)

A beta build is not releasable unless all gates pass:

1. New session command behavior:
   - `new codex` and `new claude` do not leak launcher control words into first prompt.
2. Resume/jump behavior:
   - live jump and closed-session resume are correct.
3. Session list freshness:
   - closed sessions disappear from live listing within 5 seconds after close detection.
4. Preview correctness:
   - state/title/detail rendering remains visible and accurate, with no inner-card scroll clipping.
5. Onboarding pass:
   - setup checks and recheck flow work on a clean machine profile.
6. Preferences pass:
   - hotkey changes, launch-at-login, and reindex action function correctly.

## 8. 7-Day Execution Plan

1. Day 1-2:
   - implement onboarding (2 screens) and setup checks.
2. Day 2-3:
   - implement one-page preferences and settings persistence.
3. Day 3-4:
   - diagnostics export and support surface.
4. Day 4-5:
   - finalize Flare branding consistency and beta docs.
5. Day 5-6:
   - release packaging + direct download flow, prepare Homebrew cask path.
6. Day 6-7:
   - run reliability gate suite, fix blockers only, cut invite beta.

## 9. Risk Controls

1. If onboarding implementation grows:
   - keep strict two-screen limit.
2. If preferences scope grows:
   - keep one-page format, no optional advanced controls.
3. If Homebrew timing slips:
   - ship direct download first; publish cask after release.
4. If permission handling is noisy:
   - keep onboarding completion unblocked with explicit warnings.

## 10. Acceptance Definition

Flare is beta-ready when:
1. a new invite user can complete onboarding and run their first useful action quickly,
2. core launch/resume/jump/search behavior is reliable,
3. supportability baseline exists (diagnostics export + release notes + known limitations),
4. distribution and update instructions are clear enough for external testers.
