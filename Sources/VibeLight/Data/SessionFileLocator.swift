import Foundation

final class SessionFileLocator: @unchecked Sendable {
    private struct State {
        var cache: [String: URL] = [:]
        var lookupMissAt: [String: Date] = [:]
    }

    private let lock = NSLock()
    private let lookupCooldown: TimeInterval
    private var state = State()

    init(lookupCooldown: TimeInterval = 30) {
        self.lookupCooldown = lookupCooldown
    }

    func record(sessionID: String, fileURL: URL) {
        lock.withLock {
            state.cache[sessionID] = fileURL
            state.lookupMissAt.removeValue(forKey: sessionID)
        }
    }

    func cachedFileURL(sessionID: String) -> URL? {
        lock.withLock {
            state.cache[sessionID]
        }
    }

    func fileURL(
        sessionID: String,
        sourceResolution: SessionSourceResolution,
        now: Date = Date()
    ) -> URL? {
        if let cached = cachedFileURL(sessionID: sessionID) {
            return cached
        }

        guard shouldLookup(sessionID: sessionID, now: now) else {
            return nil
        }

        if let located = locateClaudeFileURL(
            sessionID: sessionID,
            sourceResolution: sourceResolution
        ) ?? locateCodexFileURL(
            sessionID: sessionID,
            sourceResolution: sourceResolution
        ) {
            record(sessionID: sessionID, fileURL: located)
            return located
        }

        markLookupMisses(for: [sessionID], at: now)
        return nil
    }

    func prime(
        sessionIDs: Set<String>,
        toolBySessionId: [String: String],
        sourceResolution: SessionSourceResolution,
        now: Date = Date()
    ) {
        let missingClaudeIDs = missingSessionIDs(
            from: sessionIDs,
            toolBySessionId: toolBySessionId,
            tool: "claude",
            now: now
        )
        if !missingClaudeIDs.isEmpty {
            primeClaude(
                sessionIDs: missingClaudeIDs,
                sourceResolution: sourceResolution,
                now: now
            )
        }

        let missingCodexIDs = missingSessionIDs(
            from: sessionIDs,
            toolBySessionId: toolBySessionId,
            tool: "codex",
            now: now
        )
        if !missingCodexIDs.isEmpty {
            primeCodex(
                sessionIDs: missingCodexIDs,
                sourceResolution: sourceResolution,
                now: now
            )
        }
    }

    func prune(keeping sessionIDs: Set<String>) {
        lock.withLock {
            state.cache = state.cache.filter { sessionIDs.contains($0.key) }
            state.lookupMissAt = state.lookupMissAt.filter { sessionIDs.contains($0.key) }
        }
    }

    func reset() {
        lock.withLock {
            state = State()
        }
    }

    private func shouldLookup(sessionID: String, now: Date) -> Bool {
        lock.withLock {
            now.timeIntervalSince(state.lookupMissAt[sessionID] ?? .distantPast) >= lookupCooldown
        }
    }

    private func missingSessionIDs(
        from sessionIDs: Set<String>,
        toolBySessionId: [String: String],
        tool: String,
        now: Date
    ) -> [String] {
        lock.withLock {
            sessionIDs.filter { sessionID in
                toolBySessionId[sessionID] == tool
                    && state.cache[sessionID] == nil
                    && now.timeIntervalSince(state.lookupMissAt[sessionID] ?? .distantPast) >= lookupCooldown
            }
        }
    }

    private func primeClaude(
        sessionIDs: [String],
        sourceResolution: SessionSourceResolution,
        now: Date
    ) {
        let fileManager = FileManager.default
        let projectsPath = sourceResolution.claudeProjectsPath
        var unresolved = Set(sessionIDs)

        if let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) {
            for encodedProjectPath in projectDirectories where !unresolved.isEmpty {
                let directoryPath = (projectsPath as NSString).appendingPathComponent(encodedProjectPath)
                for sessionID in unresolved {
                    let candidatePath = (directoryPath as NSString)
                        .appendingPathComponent(sessionID)
                        .appending(".jsonl")
                    if fileManager.fileExists(atPath: candidatePath) {
                        record(sessionID: sessionID, fileURL: URL(fileURLWithPath: candidatePath))
                    }
                }
                unresolved = unresolved.filter { cachedFileURL(sessionID: $0) == nil }
            }
        }

        markLookupMisses(for: unresolved, at: now)
    }

    private func primeCodex(
        sessionIDs: [String],
        sourceResolution: SessionSourceResolution,
        now: Date
    ) {
        let fileManager = FileManager.default
        let codexRoot = URL(fileURLWithPath: sourceResolution.codexSessionsPath, isDirectory: true)
        var unresolved = Set(sessionIDs)

        for sessionID in sessionIDs {
            let exactPath = codexRoot
                .appendingPathComponent(sessionID)
                .appendingPathExtension("jsonl")
            if fileManager.fileExists(atPath: exactPath.path) {
                record(sessionID: sessionID, fileURL: exactPath)
            }
        }
        unresolved = unresolved.filter { cachedFileURL(sessionID: $0) == nil }

        if !unresolved.isEmpty,
           let enumerator = fileManager.enumerator(
                at: codexRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
           ) {
            for case let fileURL as URL in enumerator where !unresolved.isEmpty {
                guard fileURL.pathExtension == "jsonl" else { continue }
                let fileNameID = fileURL.deletingPathExtension().lastPathComponent
                let candidateIDs = [fileNameID, IndexingHelpers.codexSessionIDFromPath(fileURL.path)].compactMap { $0 }
                for sessionID in candidateIDs where unresolved.contains(sessionID) {
                    record(sessionID: sessionID, fileURL: fileURL)
                }
                unresolved = unresolved.filter { cachedFileURL(sessionID: $0) == nil }
            }
        }

        markLookupMisses(for: unresolved, at: now)
    }

    private func locateClaudeFileURL(
        sessionID: String,
        sourceResolution: SessionSourceResolution
    ) -> URL? {
        let fileManager = FileManager.default
        let projectsPath = sourceResolution.claudeProjectsPath

        guard let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) else {
            return nil
        }

        for encodedProjectPath in projectDirectories {
            let directoryPath = (projectsPath as NSString).appendingPathComponent(encodedProjectPath)
            let candidatePath = (directoryPath as NSString)
                .appendingPathComponent(sessionID)
                .appending(".jsonl")
            if fileManager.fileExists(atPath: candidatePath) {
                return URL(fileURLWithPath: candidatePath)
            }
        }

        return nil
    }

    private func locateCodexFileURL(
        sessionID: String,
        sourceResolution: SessionSourceResolution
    ) -> URL? {
        let fileManager = FileManager.default
        let codexRoot = URL(fileURLWithPath: sourceResolution.codexSessionsPath, isDirectory: true)
        let exactPath = codexRoot
            .appendingPathComponent(sessionID)
            .appendingPathExtension("jsonl")
        if fileManager.fileExists(atPath: exactPath.path) {
            return exactPath
        }

        guard let enumerator = fileManager.enumerator(
            at: codexRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let fileNameID = fileURL.deletingPathExtension().lastPathComponent
            let candidateIDs = [fileNameID, IndexingHelpers.codexSessionIDFromPath(fileURL.path)].compactMap { $0 }
            if candidateIDs.contains(sessionID) {
                return fileURL
            }
        }

        return nil
    }

    private func markLookupMisses<S: Sequence>(for sessionIDs: S, at now: Date) where S.Element == String {
        lock.withLock {
            for sessionID in sessionIDs where state.cache[sessionID] == nil {
                state.lookupMissAt[sessionID] = now
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
