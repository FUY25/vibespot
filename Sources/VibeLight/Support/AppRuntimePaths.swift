import Foundation

struct AppRuntimePaths {
    static let compatibilitySupportDirectoryName = VibeSpotBranding.legacyProductName

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func applicationSupportRootURL(create: Bool = true) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let rootURL = baseURL.appendingPathComponent(Self.compatibilitySupportDirectoryName, isDirectory: true)
        if create {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL
    }

    func indexesRootURL(create: Bool = true) throws -> URL {
        let indexesURL = try applicationSupportRootURL(create: create)
            .appendingPathComponent("Indexes", isDirectory: true)
        if create {
            try fileManager.createDirectory(at: indexesURL, withIntermediateDirectories: true)
        }
        return indexesURL
    }

    func legacyIndexDatabaseURL() throws -> URL {
        try applicationSupportRootURL(create: true)
            .appendingPathComponent("index.sqlite3", isDirectory: false)
    }

    func runtimeIssuesURL(createParent: Bool = true) throws -> URL {
        try applicationSupportRootURL(create: createParent)
            .appendingPathComponent("runtime-issues.json", isDirectory: false)
    }
}
