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
}
