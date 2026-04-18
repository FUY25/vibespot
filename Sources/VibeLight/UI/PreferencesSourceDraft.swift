import Foundation

struct PreferencesSourceDraft: Equatable, Sendable {
    var claude: ToolSessionSourceConfiguration
    var codex: ToolSessionSourceConfiguration

    init(
        claude: ToolSessionSourceConfiguration = ToolSessionSourceConfiguration(),
        codex: ToolSessionSourceConfiguration = ToolSessionSourceConfiguration()
    ) {
        self.claude = claude
        self.codex = codex
    }

    init(settings: AppSettings) {
        self.init(
            claude: settings.sessionSourceConfiguration.claude,
            codex: settings.sessionSourceConfiguration.codex
        )
    }

    var sessionSourceConfiguration: SessionSourceConfiguration {
        SessionSourceConfiguration(claude: claude, codex: codex)
    }

    func isDirty(comparedTo settings: AppSettings) -> Bool {
        sessionSourceConfiguration != settings.sessionSourceConfiguration
    }

    func normalized(for resolution: SessionSourceResolution) -> PreferencesSourceDraft {
        PreferencesSourceDraft(
            claude: normalizedConfiguration(for: claude, resolvedSource: resolution.claude),
            codex: normalizedConfiguration(for: codex, resolvedSource: resolution.codex)
        )
    }

    func toolsUsingAutomaticFallback(for resolution: SessionSourceResolution) -> [String] {
        var tools: [String] = []

        if usesAutomaticFallback(configuration: claude, resolvedSource: resolution.claude) {
            tools.append("Claude")
        }
        if usesAutomaticFallback(configuration: codex, resolvedSource: resolution.codex) {
            tools.append("Codex")
        }

        return tools
    }

    private func normalizedConfiguration(
        for configuration: ToolSessionSourceConfiguration,
        resolvedSource: ResolvedToolSource
    ) -> ToolSessionSourceConfiguration {
        guard usesAutomaticFallback(configuration: configuration, resolvedSource: resolvedSource) else {
            return configuration
        }

        return ToolSessionSourceConfiguration(mode: .automatic, customRoot: "")
    }

    private func usesAutomaticFallback(
        configuration: ToolSessionSourceConfiguration,
        resolvedSource: ResolvedToolSource
    ) -> Bool {
        configuration.mode == .custom && resolvedSource.status == .fallbackToAutomatic
    }
}
