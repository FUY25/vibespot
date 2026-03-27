# Design System — VibeLight

## Product Context
- **What this is:** A macOS Spotlight-style launcher for Claude and Codex CLI sessions — search, resume, switch, launch
- **Who it's for:** Developers who use Claude Code and Codex CLI daily
- **Space/industry:** Developer tools, macOS utilities, AI coding assistants
- **Project type:** Native macOS menu bar app (Swift/AppKit)

## Creative North Star: The Ethereal Terminal
Native macOS glass meets terminal soul. The interface floats in ambient depth, lit by neon data. Boundaries are tonal, not drawn. Color is reserved for the living.

### Design Principles
1. **No-Line Rule.** Boundaries through tonal shifts, not borders. Ghost borders (15% opacity) only when tonal contrast isn't enough.
2. **Ambient glow, not drop shadow.** In dark mode, floating elements emit soft neon light. In light mode, subtle tonal layering creates depth.
3. **Color means alive.** Neon green = working. Amber = waiting. Cyan = data stream. Everything dead is grayscale.
4. **Technical precision.** Tight radii (12px panel, 6px rows, 3-5px icons). No bubbly roundness. This is a control surface, not a toy.

## Aesthetic Direction
- **Direction:** Ethereal Terminal — premium macOS panel with terminal-native content
- **Decoration level:** Intentional — macOS vibrancy material IS the decoration. CRT scanline overlay in dark mode (very subtle, 0.8% opacity repeating gradient).
- **Mood:** An elite command center at midnight. Glass floating in void, illuminated by neon data streams. Light mode: crisp architectural vellum with precise green kickers.
- **Reference sites:** Warp Terminal (terminal craft), Linear (precision typography), macOS Spotlight (native panel language)

## Typography

### Bi-font strategy: The Architect + The Machine

- **Display/Hero:** Space Grotesk 700 — monospaced-adjacent geometric, premium feel. Letter-spacing: -0.04em. Use for product name, empty states.
- **Search Input:** Space Grotesk 500, 24pt — large, confident, feels like a futuristic OS prompt. Letter-spacing: -0.02em.
- **Session Titles:** JetBrains Mono 500, 14pt — THE signature move. Monospaced titles because every session came from a terminal. Letter-spacing: -0.01em.
- **Metadata (time, project, branch, tokens):** Space Grotesk 400, 12pt — secondary info in the interface font, clear hierarchy.
- **Activity Preview (tool calls, file edits):** JetBrains Mono 400, 11.5pt — data stream in the terminal voice.
- **Status Labels (WORKING, AWAITING):** JetBrains Mono 500, 10pt — uppercase, letter-spacing: 0.1em. Pure telemetry.
- **Action Hints (↩ switch, ↩ resume):** JetBrains Mono 400, 11pt — system-level affordance.
- **Section Kickers (in docs/marketing):** JetBrains Mono 500, 9pt — uppercase, letter-spacing: 0.15em, colored with `kicker` token.
- **Loading:** JetBrains Mono from Google Fonts CDN (`https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600`). Space Grotesk from Google Fonts. In the native app, JetBrains Mono is bundled; system font (SF Pro) substitutes for Space Grotesk since AppKit uses system fonts natively.

### Font Blacklist
Never use: Papyrus, Comic Sans, Lobster, Impact. Never use as primary: Inter, Roboto, Arial, Helvetica, Open Sans, Poppins, Montserrat.

### AppKit Implementation Notes
- In the native Swift app, `NSFont.monospacedSystemFont` or bundled JetBrains Mono for session titles and activity
- `.systemFont` (SF Pro) for search input, metadata, and interface text — SF Pro IS the Space Grotesk equivalent in native macOS
- The design system names (Space Grotesk, JetBrains Mono) apply to web previews and marketing; the app maps them to native equivalents

## Color

### Approach: Restrained with neon accents
Color appears only when something is alive. The panel itself uses system materials (auto light/dark via NSVisualEffectView).

### Accent Colors
| Token | Hex | Usage |
|-------|-----|-------|
| `neon` | `#AAFFDC` | Primary accent in dark mode — active state, kicker text |
| `neon-dim` | `#00E1AB` | Primary accent in light mode — kicker text, primary buttons |
| `neon-glow` | `rgba(170,255,220,0.12)` | Dark mode glow shadows, dot shadows |
| `neon-glow-strong` | `rgba(170,255,220,0.25)` | Panel top-edge gradient |
| `working-blue` | `#82AAFF` | Shimmer gradient midpoint on working session titles |
| `waiting-amber` | `#FFC965` | Breathing status text, amber status dot |
| `amber-glow` | `rgba(255,201,101,0.15)` | Amber dot box-shadow |
| `activity-cyan` | `#7DD8C0` | Activity preview text (tool calls, file edits) |
| `claude` | `#D97757` | Claude tool icon brand color |
| `codex` | `#10A37F` | Codex tool icon brand color |

### Surface Hierarchy

#### Dark Mode
| Token | Hex | Role |
|-------|-----|------|
| `bg` | `#08090A` | Base layer — the void |
| `surface` | `#111314` | Container — panels, sections |
| `surface-card` | `#161819` | Card — elevated content |

#### Light Mode
| Token | Hex | Role |
|-------|-----|------|
| `bg` | `#F4F7F6` | Base layer — architectural vellum |
| `surface` | `#E8EDEB` | Container — sections |
| `surface-card` | `#FFFFFF` | Card — elevated content |

### Label Colors

#### Dark Mode
| Token | Value | Usage |
|-------|-------|-------|
| `label` | `#DEE4E1` | Primary text |
| `label-secondary` | `rgba(222,228,225,0.5)` | Metadata, secondary info |
| `label-tertiary` | `rgba(222,228,225,0.22)` | Ghost text, placeholders, kicker lines |

#### Light Mode
| Token | Value | Usage |
|-------|-------|-------|
| `label` | `#151917` | Primary text |
| `label-secondary` | `#3A4A43` | Metadata, secondary info |
| `label-tertiary` | `rgba(58,74,67,0.35)` | Ghost text, placeholders |

### Structural Colors
| Token | Dark | Light | Usage |
|-------|------|-------|-------|
| `separator` | `rgba(255,255,255,0.04)` | `rgba(58,74,67,0.06)` | Panel separator line |
| `selection` | `rgba(170,255,220,0.06)` | `rgba(0,225,171,0.06)` | Selected row background |
| `selection-edge` | `rgba(170,255,220,0.08)` | `rgba(0,225,171,0.12)` | Selected row border (dark mode only) |
| `ghost` | `rgba(170,255,220,0.04)` | `rgba(185,203,193,0.12)` | Ghost borders, subtle dividers |
| `kicker` | `#AAFFDC` | `#006B54` | Section label text, accent text |

### Dark Mode Strategy
- Near-black surfaces with cool-neutral undertone
- Neon accents glow via box-shadow (not gradients)
- Ghost borders at 4-8% opacity replace solid lines
- Panel emits ambient radial glow (`rgba(170,255,220,0.03)`)
- Scanline overlay: `repeating-linear-gradient` at 0.8% opacity for CRT texture

### Light Mode Strategy
- Cool gray architecture with green kickers
- White cards on light gray containers — depth through luminance
- Accent colors shift to darker variants (`#006B54` kicker, `#00E1AB` neon-dim)

## Spacing
- **Base unit:** 4px
- **Density:** Compact-comfortable hybrid
- **Scale:** 4 / 8 / 10 / 12 / 14 / 16 / 22 / 24 / 32 / 48 / 64
- **Row height:** 56px (closed sessions) / 74px (with activity preview)
- **Row vertical padding:** 10px
- **Row horizontal padding:** 14px
- **Search bar height:** 64px
- **Search bar padding:** 14px top, 22px horizontal
- **Panel results padding:** 6px horizontal, 8px vertical (inner), 12px bottom
- **Logo to text gap:** 12px
- **Inter-cell spacing:** 0 (managed by row padding)

## Layout
- **Approach:** Grid-disciplined
- **Panel width:** 720px (fixed — launcher, not resizable)
- **Max visible rows:** 7
- **Positioning:** Upper portion of active screen (18% from top)

### Border Radius Scale
| Token | Value | Usage |
|-------|-------|-------|
| `radius-icon` | 3px | Tool logo icons (fallback) |
| `radius-btn` | 4px | Buttons |
| `radius-logo` | 5px | Tool logo images |
| `radius-row` | 6px | Result rows, selected state |
| `radius-card` | 10px | Cards, containers |
| `radius-panel` | 12px | Main panel |

## Motion
- **Approach:** Minimal-functional with three signature animations
- **Panel show/hide:** Instant (no bouncy transitions)

### Signature Animations

#### Shimmer (Working sessions)
- Gradient sweep across title text: `label → neon → label`
- Background-clip: text
- Duration: 2.5s, infinite, linear
- Background-size: 200%, animated from 100% to -100%

#### Breathing (Awaiting input)
- Opacity oscillation on status text: 0.4 → 0.9
- Duration: 3s, ease-in-out, infinite, alternate

#### Typing Dots (Working indicator)
- Three 3.5px dots, bouncing -3px on Y axis
- Duration: 1.4s per cycle, 0.2s stagger between dots
- Dark mode: dots use `neon` color with 4px glow shadow
- Light mode: dots use `label-tertiary` color

#### Status Dot Pulse
- Scale 1 → 1.2 and opacity 0.6 → 1
- Duration: 2s, ease-in-out, infinite
- Green dot: `neon-dim` with `neon-glow` shadow
- Amber dot: `amber` with `amber-glow` shadow

### Easing
- Enter: ease-out
- Exit: ease-in
- Move: ease-in-out

### Duration Scale
- Micro: 50-100ms (hover state changes)
- Short: 150-250ms (selection transitions)
- Medium: 250-400ms (not currently used)
- Long: 1.4s-3s (signature animations only)

## Tool Icons
- **Source:** Bundled PNGs in `Sources/VibeLight/Resources/ToolIcons/` and `Assets.xcassets`
- **Supported tools:** Claude (`claude-icon.png`), Codex (`codex-icon.png`), Gemini (`gemini-icon.png`)
- **Display size:** 22x22 in rows, 22x22 in search bar
- **Fallback:** Gray circle with first letter of tool name in white (Space Grotesk Bold)
- **Rendering:** `isTemplate = false` — show original brand colors

## Panel Appearance

### Dark Mode Panel
- Background: `rgba(17,19,20,0.82)` with `blur(48px) saturate(200%)`
- Border: `1px solid rgba(170,255,220,0.08)` (ghost border)
- Shadow: `0 0 120px rgba(170,255,220,0.04), 0 0 40px rgba(170,255,220,0.02), 0 32px 80px rgba(0,0,0,0.5)`
- Top edge: gradient line `transparent → rgba(170,255,220,0.25) → transparent` spanning 70% of width
- Selected row: `selection` background + `1px solid selection-edge` border

### Light Mode Panel
- Background: `rgba(244,247,246,0.85)` with `blur(48px) saturate(200%)`
- Border: none
- Shadow: `0 32px 80px rgba(0,0,0,0.08)`
- Selected row: `selection` background, no border

## Row States

### Live — Working
- Title: shimmer animation (neon gradient sweep)
- Status: pulsing green dot + typing dots
- Activity: cyan monospace text showing current tool/bash action
- Full opacity

### Live — Awaiting Input
- Title: full opacity, no animation
- Status: breathing amber "AWAITING" label + pulsing amber dot
- Activity: italic Space Grotesk text (assistant's last message), 55% opacity
- Full opacity

### Closed
- Title: 35% opacity, no animation
- No status indicator
- No activity line
- Metadata still visible at normal secondary opacity

### Action (New Session)
- Title: neon green color (`neon` in dark, `neon-dim` in light)
- Dark mode: `text-shadow: 0 0 12px neon-glow`
- Real tool logo icon
- Metadata shows target project directory

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-27 | Initial design system: "Ethereal Terminal" | Created by /design-consultation — native macOS craft meets terminal soul |
| 2026-03-27 | JetBrains Mono for session titles | Monospaced creates terminal-native identity; sessions ARE terminal artifacts |
| 2026-03-27 | Space Grotesk for interface text | Monospaced-adjacent geometry feels like a futuristic OS, premium over system fonts |
| 2026-03-27 | 12px panel corner radius | Tighter radii for technical precision — Spotlight's 28px felt too bubbly |
| 2026-03-27 | Near-black dark mode (#08090A) | Creates void depth for neon accents to glow against |
| 2026-03-27 | Neon green (#AAFFDC) as primary accent | Terminal energy — "alive" signals in the dark |
| 2026-03-27 | Real product logos (not letter badges) | Each row shows the actual Claude/Codex/Gemini icon for instant recognition |
| 2026-03-27 | Font size bump (14pt titles, 12pt meta, 11.5pt activity) | Readability at launcher-speed scanning |
| 2026-03-27 | CRT scanline overlay in dark mode | Subliminal terminal texture — felt, not seen |
| 2026-03-27 | Ghost borders instead of solid lines | Tonal depth over drawn boundaries — the No-Line Rule |
