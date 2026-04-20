import Foundation

struct RuntimeIssue: Codable, Equatable, Sendable {
    let recordedAt: Date
    let component: String
    let message: String
}

final class RuntimeIssueStore: @unchecked Sendable {
    static let shared = RuntimeIssueStore()

    private let fileManager: FileManager
    private let fileURL: URL?
    private let lock = NSLock()
    private var issues: [RuntimeIssue]
    private let maxIssueCount = 50

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? (try? AppRuntimePaths(fileManager: fileManager).runtimeIssuesURL())
        self.issues = []

        if let fileURL {
            self.issues = Self.loadIssues(at: fileURL)
        }
    }

    func record(component: String, message: String) {
        let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComponent.isEmpty, !trimmedMessage.isEmpty else { return }

        let issue = RuntimeIssue(recordedAt: Date(), component: trimmedComponent, message: trimmedMessage)

        lock.lock()
        issues.append(issue)
        if issues.count > maxIssueCount {
            issues.removeFirst(issues.count - maxIssueCount)
        }
        let snapshot = issues
        lock.unlock()

        persist(snapshot)
    }

    func record(component: String, error: Error) {
        record(component: component, message: error.localizedDescription)
    }

    func snapshot() -> [RuntimeIssue] {
        lock.lock()
        let snapshot = issues
        lock.unlock()
        return snapshot
    }

    private func persist(_ issues: [RuntimeIssue]) {
        guard let fileURL else { return }

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(issues).write(to: fileURL, options: .atomic)
        } catch {
            fputs("RuntimeIssueStore persist failed: \(error)\n", stderr)
        }
    }

    private static func loadIssues(at fileURL: URL) -> [RuntimeIssue] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RuntimeIssue].self, from: data)) ?? []
    }
}
