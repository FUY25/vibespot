# Releasing VibeSpot

This repo currently publishes packaged builds through GitHub Releases.

## Artifacts

The public download artifact is:

- `VibeSpot.dmg`

Build it locally with:

```bash
./scripts/package-app.sh
./scripts/create-dmg.sh
```

Verify it locally with:

```bash
./scripts/verify-packaged-app.sh
./scripts/verify-beta-install.sh
```

## Release Flow

1. Make sure the shipped app behavior matches `README.md` and `README.zh-Hans.md`.
2. Run the targeted test suite and any packaging checks you need.
3. Build `dist/VibeSpot.dmg`.
4. Draft release notes from [docs/RELEASE_TEMPLATE.md](RELEASE_TEMPLATE.md).
5. Create a GitHub Release and upload `VibeSpot.dmg`.
6. Update the release title and body to match the shipped build.

## Download Link

The README should always point users here:

- `https://github.com/FUY25/vibespot/releases`

If the repository is renamed later, update:

- `README.md`
- `README.zh-Hans.md`
- this file

## Current Distribution Notes

- The project already has packaging scripts and a DMG flow.
- Builds are currently suitable for open-source release and beta distribution.
- Official Apple signing and notarization are not required for GitHub Releases, but users may see macOS trust prompts until those are added.
