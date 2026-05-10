cask "vibespot" do
  version "0.1.0"
  sha256 "95629357c025ec570fff2032750888769b4aa74582c41c145298227faff6ce92"

  url "https://github.com/FUY25/vibespot/releases/download/v#{version}/VibeSpot.dmg"
  name "VibeSpot"
  desc "Spotlight-style launcher for Claude Code and Codex sessions"
  homepage "https://github.com/FUY25/vibespot"

  depends_on macos: ">= :sonoma"

  app "VibeSpot.app"

  zap trash: [
    "~/Library/Application Support/Flare",
    "~/Library/Application Support/VibeSpot",
    "~/Library/Preferences/com.fuyuming.Flare.plist",
    "~/Library/Preferences/com.fuyuming.VibeSpot.plist",
    "~/Library/Preferences/com.fuyuming.vibespot.plist",
    "~/Library/Saved Application State/com.fuyuming.vibespot.savedState",
  ]

  caveats <<~EOS
    VibeSpot builds are not notarized yet. If macOS blocks first launch,
    open System Settings > Privacy & Security and choose Open Anyway.
  EOS
end
