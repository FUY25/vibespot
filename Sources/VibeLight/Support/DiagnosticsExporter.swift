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
    let bundlePath: String
    let executablePath: String?
    let supportDirectoryPath: String
    let indexesDirectoryPath: String
    let launchAtLoginSupported: Bool
    let supportURL: String
    let recentIssueCount: Int
}

struct DiagnosticsResolvedToolSource: Codable, Equatable, Sendable {
    let requestedMode: String
    let customRoot: String
    let resolvedRoot: String
    let sessionsPath: String
    let status: String
    let autoAvailable: Bool
}

struct DiagnosticsSourceResolutionSnapshot: Codable, Equatable, Sendable {
    let claude: DiagnosticsResolvedToolSource
    let codex: DiagnosticsResolvedToolSource

    init(settings: AppSettings, resolution: SessionSourceResolution) {
        self.claude = DiagnosticsResolvedToolSource(
            requestedMode: settings.sessionSourceConfiguration.claude.mode.rawValue,
            customRoot: settings.sessionSourceConfiguration.claude.customRoot,
            resolvedRoot: resolution.claude.rootPath,
            sessionsPath: resolution.claude.sessionsPath,
            status: Self.describe(status: resolution.claude.status),
            autoAvailable: resolution.claude.autoAvailable
        )
        self.codex = DiagnosticsResolvedToolSource(
            requestedMode: settings.sessionSourceConfiguration.codex.mode.rawValue,
            customRoot: settings.sessionSourceConfiguration.codex.customRoot,
            resolvedRoot: resolution.codex.rootPath,
            sessionsPath: resolution.codex.sessionsPath,
            status: Self.describe(status: resolution.codex.status),
            autoAvailable: resolution.codex.autoAvailable
        )
    }

    private static func describe(status: ResolvedToolSourceStatus) -> String {
        switch status {
        case .automatic:
            return "automatic"
        case .custom:
            return "custom"
        case .fallbackToAutomatic:
            return "fallbackToAutomatic"
        case .unavailable:
            return "unavailable"
        }
    }
}

struct DiagnosticsPathSnapshot: Codable, Equatable, Sendable {
    let rootPath: String
    let exists: Bool
    let isReadable: Bool
    let hasHistory: Bool
}

struct DiagnosticsEnvironmentSnapshot: Codable, Equatable, Sendable {
    let codexBinaryPath: String?
    let claudeBinaryPath: String?
    let codexData: DiagnosticsPathSnapshot
    let claudeData: DiagnosticsPathSnapshot
}

struct DiagnosticsIndexWorkspaceSnapshot: Codable, Equatable, Sendable {
    let indexesRootPath: String
    let workspacePath: String
    let effectiveFingerprint: String
    let activeDatabasePath: String
    let activeDatabaseExists: Bool
    let activeDatabaseBytes: UInt64?
    let stagingDatabasePath: String
    let stagingDatabaseExists: Bool
    let stagingDatabaseBytes: UInt64?
}

struct DiagnosticsExporter {
    private let fileManager: FileManager
    private let issueSnapshotProvider: @Sendable () -> [RuntimeIssue]

    init(
        fileManager: FileManager = .default,
        issueSnapshotProvider: @escaping @Sendable () -> [RuntimeIssue] = { RuntimeIssueStore.shared.snapshot() }
    ) {
        self.fileManager = fileManager
        self.issueSnapshotProvider = issueSnapshotProvider
    }

    func export(settings: AppSettings, to rootDirectory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let exportDirectory = rootDirectory.appendingPathComponent("vibespot-diagnostics-\(Self.timestampString())", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)

        let runtimePaths = AppRuntimePaths(fileManager: fileManager)
        let supportDirectoryURL = try runtimePaths.applicationSupportRootURL()
        let indexesDirectoryURL = try runtimePaths.indexesRootURL()
        let sourceResolution = SessionSourceLocator(
            homeDirectoryPath: fileManager.homeDirectoryForCurrentUser.path,
            fileManager: fileManager
        ).resolve(for: settings)
        let issueSnapshot = issueSnapshotProvider()
        let environmentSnapshot = makeEnvironmentSnapshot()
        let workspaceSnapshot = makeWorkspaceSnapshot(
            indexesRootURL: indexesDirectoryURL,
            effectiveFingerprint: sourceResolution.effectiveFingerprint
        )

        let manifest = DiagnosticsExportManifest(
            generatedAt: Date(),
            applicationName: Self.infoValue("CFBundleDisplayName", default: VibeSpotBranding.productName),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            version: Self.infoValue("CFBundleShortVersionString", default: "unknown"),
            build: Self.infoValue("CFBundleVersion", default: "unknown"),
            hostName: ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            settings: settings,
            bundlePath: Bundle.main.bundleURL.path,
            executablePath: Bundle.main.executableURL?.path,
            supportDirectoryPath: supportDirectoryURL.path,
            indexesDirectoryPath: indexesDirectoryURL.path,
            launchAtLoginSupported: LaunchAtLoginManager.isSupportedRuntime(
                bundleURL: Bundle.main.bundleURL,
                bundleIdentifier: Bundle.main.bundleIdentifier
            ),
            supportURL: VibeSpotBranding.supportURL.absoluteString,
            recentIssueCount: issueSnapshot.count
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let manifestURL = exportDirectory.appendingPathComponent("manifest.json")
        let settingsURL = exportDirectory.appendingPathComponent("settings.json")
        let sourceResolutionURL = exportDirectory.appendingPathComponent("source-resolution.json")
        let environmentURL = exportDirectory.appendingPathComponent("environment-check.json")
        let workspaceURL = exportDirectory.appendingPathComponent("index-workspace.json")
        let issuesURL = exportDirectory.appendingPathComponent("runtime-issues.json")
        let readmeURL = exportDirectory.appendingPathComponent("README.txt")

        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        try encoder.encode(DiagnosticsSourceResolutionSnapshot(settings: settings, resolution: sourceResolution))
            .write(to: sourceResolutionURL, options: .atomic)
        try encoder.encode(environmentSnapshot).write(to: environmentURL, options: .atomic)
        try encoder.encode(workspaceSnapshot).write(to: workspaceURL, options: .atomic)
        try encoder.encode(issueSnapshot).write(to: issuesURL, options: .atomic)
        try Self.makeReadmeText().write(to: readmeURL, atomically: true, encoding: .utf8)

        return exportDirectory
    }

    private func makeEnvironmentSnapshot() -> DiagnosticsEnvironmentSnapshot {
        let homeDirectoryPath = fileManager.homeDirectoryForCurrentUser.path
        let codexRoot = homeDirectoryPath + "/.codex"
        let claudeRoot = homeDirectoryPath + "/.claude"

        return DiagnosticsEnvironmentSnapshot(
            codexBinaryPath: Self.which("codex"),
            claudeBinaryPath: Self.which("claude"),
            codexData: makePathSnapshot(
                rootPath: codexRoot,
                historyExists: fileManager.fileExists(atPath: codexRoot + "/session_index.jsonl")
                    || directoryContainsMatch(at: codexRoot + "/sessions", predicate: { $0.hasSuffix(".jsonl") })
            ),
            claudeData: makePathSnapshot(
                rootPath: claudeRoot,
                historyExists: directoryContainsMatch(
                    at: claudeRoot + "/projects",
                    predicate: { $0.hasSuffix(".jsonl") || $0.hasSuffix("/sessions-index.json") }
                )
            )
        )
    }

    private func makePathSnapshot(rootPath: String, historyExists: Bool) -> DiagnosticsPathSnapshot {
        let exists = fileManager.fileExists(atPath: rootPath)
        let readable = exists && fileManager.isReadableFile(atPath: rootPath)
        return DiagnosticsPathSnapshot(
            rootPath: rootPath,
            exists: exists,
            isReadable: readable,
            hasHistory: readable && historyExists
        )
    }

    private func makeWorkspaceSnapshot(
        indexesRootURL: URL,
        effectiveFingerprint: String
    ) -> DiagnosticsIndexWorkspaceSnapshot {
        let encodedFingerprint = effectiveFingerprint.utf8.map { String(format: "%02x", $0) }.joined()
        let workspaceURL = indexesRootURL.appendingPathComponent(encodedFingerprint, isDirectory: true)
        let activeURL = workspaceURL.appendingPathComponent("active.sqlite3", isDirectory: false)
        let stagingURL = workspaceURL.appendingPathComponent("staging.sqlite3", isDirectory: false)

        return DiagnosticsIndexWorkspaceSnapshot(
            indexesRootPath: indexesRootURL.path,
            workspacePath: workspaceURL.path,
            effectiveFingerprint: effectiveFingerprint,
            activeDatabasePath: activeURL.path,
            activeDatabaseExists: fileManager.fileExists(atPath: activeURL.path),
            activeDatabaseBytes: Self.fileSize(at: activeURL, fileManager: fileManager),
            stagingDatabasePath: stagingURL.path,
            stagingDatabaseExists: fileManager.fileExists(atPath: stagingURL.path),
            stagingDatabaseBytes: Self.fileSize(at: stagingURL, fileManager: fileManager)
        )
    }

    private func directoryContainsMatch(at path: String, predicate: (String) -> Bool) -> Bool {
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return false
        }

        for case let item as String in enumerator where predicate(item) {
            return true
        }
        return false
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

    private static func which(_ command: String) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> UInt64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    private static func makeReadmeText() -> String {
        """
        VibeSpot diagnostics export

        Files in this folder:
        - manifest.json: app/build/runtime summary
        - settings.json: persisted user settings
        - source-resolution.json: requested vs resolved Claude/Codex source configuration
        - environment-check.json: local binary and history visibility snapshot
        - index-workspace.json: active/staging index workspace paths and file sizes
        - runtime-issues.json: recent in-app error summaries captured during this run

        When reporting a bug, attach this folder and describe:
        1. what you tried to do
        2. what you expected
        3. what happened instead

        Support / issue tracker:
        \(VibeSpotBranding.supportURL.absoluteString)
        """
    }
}
