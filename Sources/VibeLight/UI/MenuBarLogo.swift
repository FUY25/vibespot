import AppKit

enum MenuBarLogo {
    static func makeImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        VibeSpotBranding.makeMenuBarImage(size: size)
    }
}
