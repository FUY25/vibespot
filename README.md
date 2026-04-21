# VibeSpot

VibeSpot is Spotlight for Claude Code and Codex on macOS. It helps you search old sessions, switch back to live ones, preview recent context, and start new sessions from one native command palette.

[中文说明](README.zh-Hans.md) · [Download the latest release](https://github.com/FUY25/vibespot/releases) · [Release guide](docs/RELEASING.md)

## Demo

### Activate instantly

![Quick activation demo](docs/readme-media/quick-activation.gif)

### Jump back into a live session

![Fast switch demo](docs/readme-media/fast-switch.gif)

### Fuzzy-search old sessions

![Search sessions demo](docs/readme-media/search-sessions.gif)

### Start a new session

![Start new session demo](docs/readme-media/start-new-session.gif)

## Why It Exists

Claude Code and Codex both leave useful local session data behind, but getting back to the right thread is still too slow. VibeSpot turns that local history into a fast native switcher for live runs, old context, unfinished work, and new launches.

## Features

- Search live and historical Claude and Codex sessions from a Spotlight-like panel
- Jump back to a live session with `Enter`
- Preview recent exchanges and touched files before you resume
- Fuzzy-search old threads by keyword
- Start `new claude` or `new codex` from the same surface
- Keep everything local by reading session files already on your machine

## Install

### Option 1: Download a release

1. Open the [latest release](https://github.com/FUY25/vibespot/releases).
2. Download `VibeSpot.dmg`.
3. Move `VibeSpot.app` to `/Applications`.
4. Launch it once and allow any macOS trust prompts if needed.
5. Finish onboarding.

Note: packaged builds are currently distributed without official Apple signing and notarization, so macOS may ask you to confirm that you want to open the app.

### Option 2: Build from source

```bash
git clone https://github.com/FUY25/vibespot.git vibespot
cd vibespot
./scripts/dev-run.sh
```

## Requirements

- macOS 14+
- Claude Code and/or Codex already used locally
- Session files present under `~/.claude` and/or `~/.codex`

## What VibeSpot Is Not

- Not a hosted sync product
- Not a cloud search index
- Not a replacement for Claude Code or Codex
- Not cross-platform today

## Development

Useful local commands:

```bash
./scripts/dev-run.sh
./scripts/dev-run.sh --clean
./scripts/dev-run.sh --reset-onboarding
swift test
./scripts/package-app.sh
./scripts/create-dmg.sh
```

## Open Source Status

VibeSpot is already open source and usable, but it is still early. The core app is working; the remaining work is mostly around polish, packaging, release hygiene, and public-facing documentation.

## License

[MIT](LICENSE)
