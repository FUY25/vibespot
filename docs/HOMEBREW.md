# Homebrew Install Path

VibeSpot ships a first-party Homebrew cask in this repository. The cask wraps the existing GitHub Release DMG; it does not replace the direct download flow.

## Install

```bash
brew tap FUY25/vibespot https://github.com/FUY25/vibespot.git
brew install --cask FUY25/vibespot/vibespot
```

After the tap is installed, future upgrades use the normal Homebrew command:

```bash
brew upgrade --cask FUY25/vibespot/vibespot
```

Current builds are not notarized yet, so macOS may still ask for first-launch approval in System Settings.

## Maintainer Flow

1. Build and verify the release artifact:

```bash
./scripts/package-app.sh
./scripts/create-dmg.sh
./scripts/verify-packaged-app.sh
./scripts/verify-beta-install.sh
```

2. Upload `dist/VibeSpot.dmg` to a versioned GitHub Release.

3. Update `Casks/vibespot.rb`:

```bash
./scripts/update-homebrew-cask.sh <version-or-v-prefixed-tag> dist/VibeSpot.dmg
```

The script sets `version` and `sha256` from the built DMG.

4. Validate the cask:

```bash
./scripts/verify-homebrew-cask.sh
```

5. Test a real install from the public tap after pushing:

```bash
brew untap FUY25/vibespot 2>/dev/null || true
brew tap FUY25/vibespot https://github.com/FUY25/vibespot.git
brew install --cask FUY25/vibespot/vibespot
brew uninstall --cask FUY25/vibespot/vibespot
```

## Release Rules

- Keep `Casks/vibespot.rb` downstream of immutable GitHub Release assets.
- Do not replace a published `VibeSpot.dmg` for the same version; Homebrew will reject the changed checksum.
- Do not audit this cask with `--new` until the app is ready for official `homebrew/cask`; current builds are first-party tap builds and are not notarized yet.
- Keep direct DMG install instructions in the README because Homebrew is an additional developer-friendly path, not the only supported path.
- When Developer ID signing and notarization are added, remove the cask caveat and update the README notes.
