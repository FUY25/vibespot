# Flare

Flare is Spotlight for Claude Code and Codex: a native search app that helps you find and jump between live and historical AI sessions in seconds.

Flare watches the session data already on your machine and turns it into a native Spotlight-like switcher for active runs, recent context, unfinished work, and older threads. Resuming history is supported, but the core job is faster search and faster switching across live sessions. It is macOS-first, local by default, and built for people who live inside terminal-based AI tools.

## What It Does

- Search live and historical Claude and Codex sessions from a native Spotlight-like panel
- Jump back to live sessions quickly with semantic search
- Preview recent exchanges and touched files before you jump back in
- Resume existing sessions or start a new Codex or Claude run from the same panel
- Track local activity state so you can tell what is still running and what has gone quiet

## Install

For now, the simplest path is to build from source:

```bash
git clone https://github.com/FUY25/flare.git
cd vibelight
./scripts/dev-run.sh
```

Direct equivalent:

```bash
swift run -c debug Flare
```

If you publish a release build later, the public install flow should stay just as short: download `Flare.app`, move it to `/Applications`, launch it once, then finish onboarding.

## Requirements

- macOS 14+
- local `claude` and/or `codex` usage with session files present under `~/.claude` or `~/.codex`

## Known Limitations

- macOS only
- Claude and Codex only
- reads local session files; it is not a hosted sync product
- usefulness depends on the session data those CLIs have already written locally

## Development

Useful local commands:

```bash
./scripts/dev-run.sh
./scripts/dev-run.sh --clean
./scripts/dev-run.sh --reset-onboarding
swift test
```

## Status

This repo is open source and usable now, but still early. The product shell is in place; the remaining cleanup is mostly around polish, packaging, and making the full test suite fully green.
