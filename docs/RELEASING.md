# Releasing VibeSpot

This repo currently publishes packaged builds through GitHub Releases.

## Artifacts

The public download artifact is:

- `VibeSpot.dmg`

The Homebrew cask is:

- `Casks/vibespot.rb`

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
5. Create a draft GitHub Release and upload `VibeSpot.dmg`.
6. Update the Homebrew cask with the released version and DMG checksum:

```bash
./scripts/update-homebrew-cask.sh <version-or-v-prefixed-tag> dist/VibeSpot.dmg
./scripts/verify-homebrew-cask.sh
```

7. Commit and push the cask update.
8. Test the public tap path after pushing:

```bash
brew untap FUY25/vibespot 2>/dev/null || true
brew tap FUY25/vibespot https://github.com/FUY25/vibespot.git
brew install --cask FUY25/vibespot/vibespot
brew uninstall --cask FUY25/vibespot/vibespot
```

9. Update the release title and body to match the shipped build, then publish the release.

## Download Link

The README should always point users here:

- `https://github.com/FUY25/vibespot/releases`

The README Homebrew install path should stay:

- `brew tap FUY25/vibespot https://github.com/FUY25/vibespot.git`
- `brew install --cask FUY25/vibespot/vibespot`

If the repository is renamed later, update:

- `README.md`
- `README.zh-Hans.md`
- `docs/HOMEBREW.md`
- `Casks/vibespot.rb`
- this file

## Current Distribution Notes

- The project already has packaging scripts and a DMG flow.
- The Homebrew cask is a thin wrapper around the versioned GitHub Release DMG.
- Builds are currently suitable for open-source release and beta distribution.
- Official Apple signing and notarization are not required for GitHub Releases or this first-party tap, but users may see macOS trust prompts until those are added.
