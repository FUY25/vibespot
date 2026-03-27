import AppKit

enum DesignTokens {

    // MARK: - Corner Radii

    enum Radius {
        static let icon: CGFloat = 3
        static let button: CGFloat = 4
        static let logo: CGFloat = 5
        static let row: CGFloat = 6
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
    }

    // MARK: - Spacing

    enum Spacing {
        static let panelWidth: CGFloat = 720
        static let searchBarHeight: CGFloat = 64
        static let searchFieldHeight: CGFloat = 40
        static let rowHeightClosed: CGFloat = 56
        static let rowHeightActive: CGFloat = 74
        static let rowVerticalPadding: CGFloat = 10
        static let rowHorizontalPadding: CGFloat = 14
        static let logoToTextGap: CGFloat = 12
        static let searchBarTopPadding: CGFloat = 14
        static let searchBarHorizontalPadding: CGFloat = 22
        static let resultsHorizontalPadding: CGFloat = 6
        static let resultsBottomPadding: CGFloat = 12
        static let toolIconSize: CGFloat = 22
        static let maxVisibleRows: Int = 7
    }

    // MARK: - Typography

    enum Font {
        nonisolated(unsafe) static let sessionTitle: NSFont = .monospacedSystemFont(ofSize: 14, weight: .medium)
        nonisolated(unsafe) static let searchInput: NSFont = .systemFont(ofSize: 24, weight: .medium)
        nonisolated(unsafe) static let metadata: NSFont = .systemFont(ofSize: 12, weight: .regular)
        nonisolated(unsafe) static let activity: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        nonisolated(unsafe) static let statusLabel: NSFont = .monospacedSystemFont(ofSize: 10, weight: .medium)
        nonisolated(unsafe) static let actionHint: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    // MARK: - Colors

    enum Color {
        static let neon = NSColor(srgbRed: 170/255, green: 255/255, blue: 220/255, alpha: 1)
        static let neonDim = NSColor(srgbRed: 0, green: 225/255, blue: 171/255, alpha: 1)
        static let workingBlue = NSColor(srgbRed: 130/255, green: 170/255, blue: 255/255, alpha: 1)
        static let waitingAmber = NSColor(srgbRed: 255/255, green: 201/255, blue: 101/255, alpha: 1)
        static let activityCyan = NSColor(srgbRed: 125/255, green: 216/255, blue: 192/255, alpha: 1)

        static let ghostBorder = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 170/255, green: 255/255, blue: 220/255, alpha: 0.08)
            } else {
                return NSColor.clear
            }
        }

        static let selection = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 170/255, green: 255/255, blue: 220/255, alpha: 0.06)
            } else {
                return NSColor(srgbRed: 0, green: 225/255, blue: 171/255, alpha: 0.06)
            }
        }

        static let selectionEdge = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 170/255, green: 255/255, blue: 220/255, alpha: 0.08)
            } else {
                return NSColor.clear
            }
        }

        static let neonGlow = NSColor(srgbRed: 170/255, green: 255/255, blue: 220/255, alpha: 0.12)
        static let amberGlow = NSColor(srgbRed: 255/255, green: 201/255, blue: 101/255, alpha: 0.15)
        static let closedTitleAlpha: CGFloat = 0.35
    }

    // MARK: - Animation

    enum Animation {
        static let shimmerDuration: CFTimeInterval = 2.5
        static let breathingDuration: CFTimeInterval = 3.0
        static let breathingFromOpacity: Float = 0.4
        static let breathingToOpacity: Float = 0.9
        static let typingDotDuration: CFTimeInterval = 1.4
        static let typingDotStagger: CFTimeInterval = 0.2
        static let typingDotSize: CGFloat = 3.5
        static let typingDotBounce: CGFloat = -3
        static let statusDotPulseDuration: CFTimeInterval = 2.0
    }
}
