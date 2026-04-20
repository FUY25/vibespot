import Foundation

enum ResourceBundleLocator {
    static let current: Bundle = {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Flare_Flare.bundle", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Flare_Flare.bundle", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Flare_Flare.bundle", isDirectory: true),
        ]

        for case let candidateURL? in candidates {
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        return Bundle.module
    }()
}
