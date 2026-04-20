import Foundation

struct DiagnosticsExportManifest: Codable, Equatable, Sendable {
    let generatedAt: Date
    let applicationName: String
    let bundleIdentifier: String
    let version: String
    let build: String
    let hostName: String
    let operatingSystem: String
    let settings: AppSettings
}

struct DiagnosticsExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(settings: AppSettings, to rootDirectory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let exportDirectory = rootDirectory.appendingPathComponent("vibespot-diagnostics-\(Self.timestampString())", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)

        let manifest = DiagnosticsExportManifest(
            generatedAt: Date(),
            applicationName: Self.infoValue("CFBundleDisplayName", default: VibeSpotBranding.productName),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            version: Self.infoValue("CFBundleShortVersionString", default: "unknown"),
            build: Self.infoValue("CFBundleVersion", default: "unknown"),
            hostName: ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            settings: settings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let manifestURL = exportDirectory.appendingPathComponent("manifest.json")
        let settingsURL = exportDirectory.appendingPathComponent("settings.json")

        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)

        return exportDirectory
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func infoValue(_ key: String, default fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }
}
