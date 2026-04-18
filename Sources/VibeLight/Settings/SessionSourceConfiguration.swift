import Foundation

enum SessionSourceMode: String, Codable, Sendable {
    case automatic
    case custom
}

struct ToolSessionSourceConfiguration: Codable, Equatable, Sendable {
    var mode: SessionSourceMode = .automatic
    var customRoot: String = ""
}

struct SessionSourceConfiguration: Codable, Equatable, Sendable {
    var claude: ToolSessionSourceConfiguration
    var codex: ToolSessionSourceConfiguration

    static let `default` = SessionSourceConfiguration()

    init(
        claude: ToolSessionSourceConfiguration = ToolSessionSourceConfiguration(),
        codex: ToolSessionSourceConfiguration = ToolSessionSourceConfiguration()
    ) {
        self.claude = claude
        self.codex = codex
    }

    init(
        mode: SessionSourceMode,
        customClaudeRoot: String,
        customCodexRoot: String
    ) {
        self.init(
            claude: ToolSessionSourceConfiguration(mode: mode, customRoot: customClaudeRoot),
            codex: ToolSessionSourceConfiguration(mode: mode, customRoot: customCodexRoot)
        )
    }

    var mode: SessionSourceMode {
        get {
            if claude.mode == codex.mode {
                return claude.mode
            }
            return claude.mode == .custom || codex.mode == .custom ? .custom : .automatic
        }
        set {
            claude.mode = newValue
            codex.mode = newValue
        }
    }

    var customClaudeRoot: String {
        get { claude.customRoot }
        set { claude.customRoot = newValue }
    }

    var customCodexRoot: String {
        get { codex.customRoot }
        set { codex.customRoot = newValue }
    }

    var hasCustomEntries: Bool {
        !customClaudeRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !customCodexRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case claude
        case codex
        case mode
        case customClaudeRoot
        case customCodexRoot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedClaude = try container.decodeIfPresent(ToolSessionSourceConfiguration.self, forKey: .claude)
        let decodedCodex = try container.decodeIfPresent(ToolSessionSourceConfiguration.self, forKey: .codex)
        if decodedClaude != nil || decodedCodex != nil {
            self.init(
                claude: decodedClaude ?? ToolSessionSourceConfiguration(),
                codex: decodedCodex ?? ToolSessionSourceConfiguration()
            )
            return
        }

        let legacyMode = try container.decodeIfPresent(SessionSourceMode.self, forKey: .mode) ?? .automatic
        let legacyClaudeRoot = try container.decodeIfPresent(String.self, forKey: .customClaudeRoot) ?? ""
        let legacyCodexRoot = try container.decodeIfPresent(String.self, forKey: .customCodexRoot) ?? ""
        self.init(
            claude: ToolSessionSourceConfiguration(mode: legacyMode, customRoot: legacyClaudeRoot),
            codex: ToolSessionSourceConfiguration(mode: legacyMode, customRoot: legacyCodexRoot)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(claude, forKey: .claude)
        try container.encode(codex, forKey: .codex)
    }
}

enum ResolvedToolSourceStatus: Equatable, Sendable {
    case automatic
    case custom
    case fallbackToAutomatic
    case unavailable
}

struct ResolvedToolSource: Equatable, Sendable {
    let rootPath: String
    let sessionsPath: String
    let status: ResolvedToolSourceStatus
    let autoAvailable: Bool
}

struct SessionSourceResolution: Equatable, Sendable {
    let claude: ResolvedToolSource
    let codex: ResolvedToolSource
    let effectiveFingerprint: String

    init(claude: ResolvedToolSource, codex: ResolvedToolSource) {
        self.claude = claude
        self.codex = codex
        self.effectiveFingerprint = Self.makeEffectiveFingerprint(
            claudeRootPath: claude.rootPath,
            codexRootPath: codex.rootPath
        )
    }

    init(
        claudeRootPath: String,
        codexRootPath: String,
        claudeProjectsPath: String,
        claudeSessionsPath: String,
        codexSessionsPath: String,
        codexStatePath: String,
        autoClaudeAvailable: Bool,
        autoCodexAvailable: Bool,
        usingCustomClaude: Bool,
        usingCustomCodex: Bool,
        customRequestedButUnavailable: Bool,
        autoFallbackForClaude: Bool,
        autoFallbackForCodex: Bool,
        requestedMode: SessionSourceMode
    ) {
        let claudeStatus = Self.legacyStatus(
            usingCustom: usingCustomClaude,
            autoFallback: autoFallbackForClaude,
            autoAvailable: autoClaudeAvailable
        )
        let codexStatus = Self.legacyStatus(
            usingCustom: usingCustomCodex,
            autoFallback: autoFallbackForCodex,
            autoAvailable: autoCodexAvailable
        )

        self.init(
            claude: ResolvedToolSource(
                rootPath: claudeRootPath,
                sessionsPath: claudeSessionsPath,
                status: claudeStatus,
                autoAvailable: autoClaudeAvailable
            ),
            codex: ResolvedToolSource(
                rootPath: codexRootPath,
                sessionsPath: codexSessionsPath,
                status: codexStatus,
                autoAvailable: autoCodexAvailable
            )
        )
    }

    var claudeRootPath: String { claude.rootPath }
    var codexRootPath: String { codex.rootPath }
    var claudeProjectsPath: String { claude.rootPath + "/projects" }
    var claudeSessionsPath: String { claude.sessionsPath }
    var codexSessionsPath: String { codex.sessionsPath }
    var codexStatePath: String { codex.rootPath + "/state_5.sqlite" }

    var autoClaudeAvailable: Bool { claude.autoAvailable }
    var autoCodexAvailable: Bool { codex.autoAvailable }
    var usingCustomClaude: Bool { claude.status == .custom }
    var usingCustomCodex: Bool { codex.status == .custom }
    var customRequestedButUnavailable: Bool {
        claude.status == .unavailable || codex.status == .unavailable
    }
    var autoFallbackForClaude: Bool { claude.status == .fallbackToAutomatic }
    var autoFallbackForCodex: Bool { codex.status == .fallbackToAutomatic }
    var requestedMode: SessionSourceMode {
        if claude.status == .automatic && codex.status == .automatic {
            return .automatic
        }
        return .custom
    }

    static func == (lhs: SessionSourceResolution, rhs: SessionSourceResolution) -> Bool {
        lhs.effectiveFingerprint == rhs.effectiveFingerprint
    }

    private static func makeEffectiveFingerprint(claudeRootPath: String, codexRootPath: String) -> String {
        "\(claudeRootPath)\u{0}\(codexRootPath)"
    }

    private static func legacyStatus(
        usingCustom: Bool,
        autoFallback: Bool,
        autoAvailable: Bool
    ) -> ResolvedToolSourceStatus {
        if usingCustom {
            return .custom
        }
        if autoFallback {
            return .fallbackToAutomatic
        }
        if autoAvailable {
            return .automatic
        }
        return .unavailable
    }
}

struct SessionSourceLocator {
    private let homeDirectoryPath: String
    private let fileManager: FileManager

    init(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryPath = homeDirectoryPath
        self.fileManager = fileManager
    }

    func resolve(for settings: AppSettings) -> SessionSourceResolution {
        let autoClaudeRoot = homeDirectoryPath + "/.claude"
        let autoCodexRoot = homeDirectoryPath + "/.codex"
        let autoClaudeAvailable = isExistingDirectory(autoClaudeRoot)
        let autoCodexAvailable = isExistingDirectory(autoCodexRoot)

        let claudeResolution = resolveToolSource(
            requestedMode: settings.sessionSourceConfiguration.claude.mode,
            customRoot: settings.sessionSourceConfiguration.claude.customRoot,
            selectable: isClaudeRootSelectable,
            autoRoot: autoClaudeRoot,
            autoAvailable: autoClaudeAvailable
        )
        let codexResolution = resolveToolSource(
            requestedMode: settings.sessionSourceConfiguration.codex.mode,
            customRoot: settings.sessionSourceConfiguration.codex.customRoot,
            selectable: isCodexRootSelectable,
            autoRoot: autoCodexRoot,
            autoAvailable: autoCodexAvailable
        )

        return SessionSourceResolution(
            claude: claudeResolution,
            codex: codexResolution
        )
    }

    func isClaudeRootSelectable(_ path: String) -> Bool {
        guard let normalized = normalizedExistingDirectoryPath(path) else { return false }
        let fm = fileManager
        let candidates = [
            (normalized as NSString).appendingPathComponent("projects"),
            (normalized as NSString).appendingPathComponent("sessions"),
        ]
        return candidates.allSatisfy {
            var isDirectory = ObjCBool(false)
            return fm.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    func isCodexRootSelectable(_ path: String) -> Bool {
        guard let normalized = normalizedExistingDirectoryPath(path) else { return false }
        let fm = fileManager
        let candidates = [
            (normalized as NSString).appendingPathComponent("sessions"),
            (normalized as NSString).appendingPathComponent("state_5.sqlite"),
        ]

        var isDirectory = ObjCBool(false)
        let hasSessions = fm.fileExists(atPath: candidates[0], isDirectory: &isDirectory) && isDirectory.boolValue
        let hasState = fm.fileExists(atPath: candidates[1])
        return hasSessions && hasState
    }

    private func resolveToolSource(
        requestedMode: SessionSourceMode,
        customRoot: String,
        selectable: (String) -> Bool,
        autoRoot: String,
        autoAvailable: Bool
    ) -> ResolvedToolSource {
        let normalizedCustomRoot = normalizePath(customRoot)
        let customRootIsSelectable = normalizedCustomRoot.map { selectable($0) } ?? false

        let resolvedRootPath: String
        let status: ResolvedToolSourceStatus

        switch requestedMode {
        case .custom:
            if let normalizedCustomRoot, customRootIsSelectable {
                resolvedRootPath = normalizedCustomRoot
                status = .custom
            } else if autoAvailable {
                resolvedRootPath = autoRoot
                status = .fallbackToAutomatic
            } else {
                resolvedRootPath = autoRoot
                status = .unavailable
            }
        case .automatic:
            if autoAvailable {
                resolvedRootPath = autoRoot
                status = .automatic
            } else if let normalizedCustomRoot, customRootIsSelectable {
                resolvedRootPath = normalizedCustomRoot
                status = .custom
            } else {
                resolvedRootPath = autoRoot
                status = .unavailable
            }
        }

        return ResolvedToolSource(
            rootPath: resolvedRootPath,
            sessionsPath: resolvedRootPath + "/sessions",
            status: status,
            autoAvailable: autoAvailable
        )
    }

    private func normalizePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private func existingDirectoryPath(_ path: String) -> String? {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return path
    }

    private func normalizedExistingDirectoryPath(_ path: String) -> String? {
        let normalized = normalizePath(path)
        guard let expanded = normalized else { return nil }
        return existingDirectoryPath(expanded) != nil ? expanded : nil
    }

    private func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
