import ServiceManagement

protocol LaunchAtLoginManaging {
    var isSupportedRuntime: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    private let bundleURL: URL
    private let bundleIdentifier: String?

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isSupportedRuntime else {
            return
        }

        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    var isSupportedRuntime: Bool {
        Self.isSupportedRuntime(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
    }

    static func isSupportedRuntime(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        bundleURL.pathExtension == "app" && !(bundleIdentifier?.isEmpty ?? true)
    }
}
