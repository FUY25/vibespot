import AppKit

private enum SourceTool: String {
    case claude = "Claude"
    case codex = "Codex"
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let launchAtLoginSupported: Bool
    private let sessionSourceLocator: SessionSourceLocator
    private let onApplySettings: @MainActor @Sendable (AppSettings) -> Void
    private let onReindex: @MainActor @Sendable () -> Void
    private let onExportDiagnostics: @MainActor @Sendable () -> Void

    private var settings: AppSettings
    private var sourceDraft: PreferencesSourceDraft
    private var statusMessage: String = ""

    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginToggle = NSSwitch(frame: .zero)
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let searchHistoryToggle = NSSwitch(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")

    private let claudeSourceModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let codexSourceModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let claudeRootStatusLabel = NSTextField(labelWithString: "")
    private let codexRootStatusLabel = NSTextField(labelWithString: "")
    private let claudeRootPathButton = NSButton(title: "Choose", target: nil, action: nil)
    private let codexRootPathButton = NSButton(title: "Choose", target: nil, action: nil)
    private let sourceWarningLabel = NSTextField(wrappingLabelWithString: "")
    private let sourceApplyButton = NSButton(title: "Apply", target: nil, action: nil)

    private let contentStack = NSStackView()
    private var shortcutCaptureWindowController: ShortcutCaptureWindowController?

    private let windowWidth: CGFloat = 648
    private let windowHeight: CGFloat = 612
    private let contentColumnWidth: CGFloat = 560
    private let rowWidth: CGFloat = 520

    init(
        settingsStore: SettingsStore,
        launchAtLoginSupported: Bool = LaunchAtLoginManager().isSupportedRuntime,
        sessionSourceLocator: SessionSourceLocator = SessionSourceLocator(),
        onApplySettings: @escaping @MainActor @Sendable (AppSettings) -> Void,
        onReindex: @escaping @MainActor @Sendable () -> Void,
        onExportDiagnostics: @escaping @MainActor @Sendable () -> Void
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginSupported = launchAtLoginSupported
        self.sessionSourceLocator = sessionSourceLocator
        self.onApplySettings = onApplySettings
        self.onReindex = onReindex
        self.onExportDiagnostics = onExportDiagnostics
        self.settings = settingsStore.load()
        self.sourceDraft = PreferencesSourceDraft(settings: self.settings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)

        configureWindow()
        buildContent()
        loadControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreferences() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func syncSettings(_ newSettings: AppSettings) {
        let hadDirtyDraft = sourceDraft.isDirty(comparedTo: settings)
        settings = newSettings
        if hadDirtyDraft == false {
            sourceDraft = PreferencesSourceDraft(settings: newSettings)
        }
        loadControls()
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18

        documentView.addSubview(contentStack)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -26),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 26),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -26),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -52),
        ])

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(launchAtLoginChanged)
        searchHistoryToggle.target = self
        searchHistoryToggle.action = #selector(historyModeChanged)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        claudeSourceModePopup.target = self
        claudeSourceModePopup.action = #selector(claudeSourceModeChanged)
        codexSourceModePopup.target = self
        codexSourceModePopup.action = #selector(codexSourceModeChanged)
        claudeRootPathButton.target = self
        claudeRootPathButton.action = #selector(chooseClaudeRootPath)
        codexRootPathButton.target = self
        codexRootPathButton.action = #selector(chooseCodexRootPath)
        sourceApplyButton.target = self
        sourceApplyButton.action = #selector(applySourceChanges)
    }

    private func buildContent() {
        let views = [
            makeHeaderView(),
            makeSystemSection(),
            makeSourceSection(),
            makeMaintenanceSection(),
            makeAboutSection(),
            makeStatusView(),
        ]

        views.forEach { contentStack.addArrangedSubview($0) }
    }

    private func makeHeaderView() -> NSView {
        let kicker = makeKickerLabel("PREFERENCES")
        kicker.textColor = .controlAccentColor

        let title = NSTextField(labelWithString: "Preferences")
        title.font = NSFont.systemFont(ofSize: 26, weight: .semibold)

        let subtitle = NSTextField(
            wrappingLabelWithString: "A compact single-page window for app behavior, staged session sources, and local build details."
        )
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3

        let stack = NSStackView(views: [kicker, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func makeSystemSection() -> NSView {
        makeSectionCard(
            title: "SYSTEM",
            rows: [
                makeToggleRow(
                    title: "Launch at login",
                    subtitle: launchAtLoginSupported
                        ? "Open Flare automatically when you sign in."
                        : "Available in packaged app builds. It is disabled while running from source.",
                    toggle: launchAtLoginToggle
                ),
                makeThemeRow(),
                makeShortcutRow(),
                makeToggleRow(
                    title: "Search history",
                    subtitle: "Include closed sessions in search results.",
                    toggle: searchHistoryToggle
                ),
            ]
        )
    }

    private func makeSourceSection() -> NSView {
        sourceWarningLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sourceWarningLabel.textColor = .systemYellow
        sourceWarningLabel.maximumNumberOfLines = 3
        sourceWarningLabel.isHidden = true

        sourceApplyButton.bezelStyle = .rounded

        let footnote = makeFootnote("Source edits stay local in this window until you click Apply.")
        let sourceStack = NSStackView(views: [
            footnote,
            makeToolSourceEditor(
                title: SourceTool.claude.rawValue,
                modePopup: claudeSourceModePopup,
                statusLabel: claudeRootStatusLabel,
                rootButton: claudeRootPathButton
            ),
            makeToolSourceEditor(
                title: SourceTool.codex.rawValue,
                modePopup: codexSourceModePopup,
                statusLabel: codexRootStatusLabel,
                rootButton: codexRootPathButton
            ),
            sourceWarningLabel,
            makeTrailingControlRow(
                title: "Staged source changes",
                subtitle: "Apply only when the edited configuration is valid.",
                control: sourceApplyButton
            ),
        ])
        sourceStack.orientation = .vertical
        sourceStack.alignment = .leading
        sourceStack.spacing = 12

        return makeSectionCard(
            title: "SESSION SOURCES",
            customBody: sourceStack
        )
    }

    private func makeMaintenanceSection() -> NSView {
        makeSectionCard(
            title: "MAINTENANCE",
            rows: [
                makeActionRow(
                    title: "Reindex sessions",
                    subtitle: "Refresh the local search index from your Claude and Codex session files.",
                    buttonTitle: "Reindex Now",
                    action: #selector(reindexAction)
                ),
                makeActionRow(
                    title: "Export diagnostics",
                    subtitle: "Create a local diagnostics snapshot for debugging or issue reports.",
                    buttonTitle: "Export",
                    action: #selector(exportDiagnosticsAction)
                ),
            ]
        )
    }

    private func makeAboutSection() -> NSView {
        makeSectionCard(
            title: "ABOUT",
            rows: [
                makeValueRow(title: "Version", value: bundleShortVersion),
                makeValueRow(title: "Build", value: bundleBuildVersion),
            ]
        )
    }

    private func makeStatusView() -> NSView {
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        return statusLabel
    }

    private func makeSectionCard(title: String, rows: [NSView]) -> NSView {
        let bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 0

        rows.enumerated().forEach { index, row in
            bodyStack.addArrangedSubview(row)
            if index < rows.count - 1 {
                bodyStack.addArrangedSubview(makeSeparator())
            }
        }

        return makeSectionCard(title: title, customBody: bodyStack)
    }

    private func makeSectionCard(title: String, customBody: NSView) -> NSView {
        let card = makeCard()
        let heading = makeKickerLabel(title)
        let stack = NSStackView(views: [heading, customBody])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: contentColumnWidth),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeCard() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        return card
    }

    private func makeToggleRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = makeBaseRow()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 3

        let textStack = makeRowTextStack(titleLabel: titleLabel, subtitleLabel: subtitleLabel)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
        ])

        return row
    }

    private func makeThemeRow() -> NSView {
        configurePopup(themePopup, items: ["System", "Light", "Dark"])
        return makeTrailingControlRow(
            title: "Appearance",
            subtitle: "Match the system or pin Flare to a single appearance.",
            control: themePopup
        )
    }

    private func makeShortcutRow() -> NSView {
        styleShortcutValueLabel()

        let changeButton = NSButton(title: "Change Shortcut", target: self, action: #selector(changeShortcutAction))
        changeButton.bezelStyle = .rounded
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetShortcutAction))
        resetButton.bezelStyle = .recessed

        let trailing = NSStackView(views: [shortcutValueLabel, changeButton, resetButton])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 8

        return makeTrailingControlRow(
            title: "Shortcut",
            subtitle: "Choose the global shortcut that opens Flare anywhere.",
            control: trailing
        )
    }

    private func styleShortcutValueLabel() {
        shortcutValueLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        shortcutValueLabel.alignment = .center
        shortcutValueLabel.wantsLayer = true
        shortcutValueLabel.layer?.cornerRadius = 8
        shortcutValueLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        shortcutValueLabel.textColor = .controlAccentColor
        shortcutValueLabel.translatesAutoresizingMaskIntoConstraints = false
        if shortcutValueLabel.constraints.isEmpty {
            NSLayoutConstraint.activate([
                shortcutValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),
                shortcutValueLabel.heightAnchor.constraint(equalToConstant: 30),
            ])
        }
    }

    private func makeToolSourceEditor(
        title: String,
        modePopup: NSPopUpButton,
        statusLabel: NSTextField,
        rootButton: NSButton
    ) -> NSView {
        configurePopup(modePopup, items: ["Automatic", "Custom"])

        rootButton.bezelStyle = .rounded
        rootButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])

        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2

        let heading = makeKickerLabel(title.uppercased())
        let stack = NSStackView(views: [
            heading,
            makeTrailingControlRow(
                title: "Mode",
                subtitle: "Automatic and custom are staged independently for \(title).",
                control: modePopup
            ),
            makeButtonRow(
                title: "Root",
                subtitleLabel: statusLabel,
                button: rootButton
            ),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        return stack
    }

    private func makeButtonRow(title: String, subtitleLabel: NSTextField, button: NSButton) -> NSView {
        let row = makeBaseRow()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        row.addSubview(textStack)
        row.addSubview(button)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),
        ])

        return row
    }

    private func makeActionRow(title: String, subtitle: String, buttonTitle: String, action: Selector) -> NSView {
        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded
        return makeTrailingControlRow(title: title, subtitle: subtitle, control: button)
    }

    private func makeValueRow(title: String, value: String) -> NSView {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        return makeTrailingControlRow(title: title, subtitle: "", control: valueLabel, includeSubtitle: false)
    }

    private func makeTrailingControlRow(title: String, subtitle: String, control: NSView, includeSubtitle: Bool = true) -> NSView {
        let row = makeBaseRow()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.isHidden = includeSubtitle == false

        let textStack = makeRowTextStack(titleLabel: titleLabel, subtitleLabel: subtitleLabel, includeSubtitle: includeSubtitle)
        control.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
        ])

        return row
    }

    private func makeFootnote(_ text: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true

        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2

        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
        ])
        return row
    }

    private func makeBaseRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: rowWidth),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        return row
    }

    private func makeRowTextStack(
        titleLabel: NSTextField,
        subtitleLabel: NSTextField,
        includeSubtitle: Bool = true
    ) -> NSStackView {
        let views = includeSubtitle ? [titleLabel, subtitleLabel] : [titleLabel]
        let textStack = NSStackView(views: views)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = includeSubtitle ? 3 : 0
        return textStack
    }

    private func makeSeparator() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: rowWidth),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return line
    }

    private func makeKickerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configurePopup(_ popup: NSPopUpButton, items: [String]) {
        popup.removeAllItems()
        popup.addItems(withTitles: items)
    }

    private func loadControls() {
        themePopup.selectItem(withTitle: selectedThemeLabel(for: settings.theme))
        launchAtLoginToggle.state = settings.launchAtLogin ? .on : .off
        launchAtLoginToggle.isEnabled = launchAtLoginSupported
        shortcutValueLabel.stringValue = settings.hotkeyBinding.displayString
        searchHistoryToggle.state = settings.historyMode == .liveAndHistory ? .on : .off

        claudeSourceModePopup.selectItem(withTitle: sourceDraft.claude.mode == .automatic ? "Automatic" : "Custom")
        codexSourceModePopup.selectItem(withTitle: sourceDraft.codex.mode == .automatic ? "Automatic" : "Custom")

        let stagedSettings = stagedSourceSettings()
        let resolution = sessionSourceLocator.resolve(for: stagedSettings)

        claudeRootStatusLabel.stringValue = sourceSummaryText(
            configuration: sourceDraft.claude,
            resolvedSource: resolution.claude,
            selectable: sessionSourceLocator.isClaudeRootSelectable(sourceDraft.claude.customRoot)
        )
        claudeRootStatusLabel.textColor = sourceStatusColor(
            configuration: sourceDraft.claude,
            resolvedSource: resolution.claude
        )

        codexRootStatusLabel.stringValue = sourceSummaryText(
            configuration: sourceDraft.codex,
            resolvedSource: resolution.codex,
            selectable: sessionSourceLocator.isCodexRootSelectable(sourceDraft.codex.customRoot)
        )
        codexRootStatusLabel.textColor = sourceStatusColor(
            configuration: sourceDraft.codex,
            resolvedSource: resolution.codex
        )

        claudeRootPathButton.isEnabled = sourceDraft.claude.mode == .custom
        claudeRootPathButton.alphaValue = sourceDraft.claude.mode == .custom ? 1 : 0.55
        codexRootPathButton.isEnabled = sourceDraft.codex.mode == .custom
        codexRootPathButton.alphaValue = sourceDraft.codex.mode == .custom ? 1 : 0.55

        let warning = sourceWarningMessage(for: resolution)
        sourceWarningLabel.stringValue = warning ?? ""
        sourceWarningLabel.isHidden = warning == nil

        sourceApplyButton.isEnabled = sourceDraft.isDirty(comparedTo: settings) && warning == nil
        refreshStatusLabel()
    }

    private func stagedSourceSettings() -> AppSettings {
        var stagedSettings = settings
        stagedSettings.sessionSourceConfiguration = sourceDraft.sessionSourceConfiguration
        return stagedSettings
    }

    private func refreshStatusLabel() {
        statusLabel.stringValue = statusMessage.isEmpty ? defaultStatusMessage : statusMessage
    }

    private var defaultStatusMessage: String {
        if launchAtLoginSupported {
            return "Theme, shortcut, history, and launch settings save immediately. Source changes stay staged until Apply."
        }
        return "Theme, shortcut, and history save immediately. Launch at login requires a packaged build. Source changes stay staged until Apply."
    }

    private func sourceSummaryText(
        configuration: ToolSessionSourceConfiguration,
        resolvedSource: ResolvedToolSource,
        selectable: Bool
    ) -> String {
        let customPath = compactPath(configuration.customRoot)

        switch configuration.mode {
        case .automatic:
            switch resolvedSource.status {
            case .automatic:
                return "Automatic: \(compactPath(resolvedSource.rootPath))"
            case .custom:
                return "Automatic unavailable, valid custom root ready: \(customPath)"
            case .fallbackToAutomatic:
                return "Automatic fallback: \(compactPath(resolvedSource.rootPath))"
            case .unavailable:
                return "Automatic unavailable"
            }

        case .custom:
            if selectable {
                return "Custom: \(customPath)"
            }
            if configuration.customRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Custom root not selected"
            }
            if resolvedSource.status == .fallbackToAutomatic {
                return "Invalid custom root. Automatic fallback available: \(compactPath(resolvedSource.rootPath))"
            }
            return "Invalid custom root. No fallback available."
        }
    }

    private func sourceStatusColor(
        configuration: ToolSessionSourceConfiguration,
        resolvedSource: ResolvedToolSource
    ) -> NSColor {
        if configuration.mode == .custom,
           configuration.customRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           resolvedSource.status == .unavailable {
            return .systemYellow
        }
        if resolvedSource.status == .fallbackToAutomatic {
            return .systemYellow
        }
        return .secondaryLabelColor
    }

    private func sourceWarningMessage(for resolution: SessionSourceResolution) -> String? {
        var invalidTools: [String] = []

        if sourceDraft.claude.mode == .custom, resolution.claude.status == .unavailable {
            invalidTools.append(SourceTool.claude.rawValue)
        }
        if sourceDraft.codex.mode == .custom, resolution.codex.status == .unavailable {
            invalidTools.append(SourceTool.codex.rawValue)
        }

        guard invalidTools.isEmpty == false else {
            return nil
        }

        let toolSummary: String
        if invalidTools.count == 2 {
            toolSummary = "Claude and Codex"
        } else {
            toolSummary = invalidTools[0]
        }

        return "\(toolSummary) source selection is invalid and there is no automatic fallback. The current active source stays active until you apply valid settings."
    }

    private func compactPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "not set" }
        if trimmed.count <= 52 {
            return trimmed
        }
        return "…\(trimmed.suffix(48))"
    }

    private func saveSettings(status: String) {
        settingsStore.save(settings)
        onApplySettings(settings)
        statusMessage = status
        loadControls()
    }

    @objc private func launchAtLoginChanged() {
        guard launchAtLoginSupported else { return }
        settings.launchAtLogin = launchAtLoginToggle.state == .on
        saveSettings(status: "Launch setting updated")
    }

    @objc private func historyModeChanged() {
        settings.historyMode = searchHistoryToggle.state == .on ? .liveAndHistory : .liveOnly
        saveSettings(status: "Search mode updated")
    }

    @objc private func themeChanged() {
        settings.theme = selectedTheme
        saveSettings(status: "Appearance updated")
    }

    @objc private func claudeSourceModeChanged() {
        sourceDraft.claude.mode = claudeSourceModePopup.titleOfSelectedItem == "Custom" ? .custom : .automatic
        statusMessage = ""
        loadControls()
    }

    @objc private func codexSourceModeChanged() {
        sourceDraft.codex.mode = codexSourceModePopup.titleOfSelectedItem == "Custom" ? .custom : .automatic
        statusMessage = ""
        loadControls()
    }

    @objc private func chooseClaudeRootPath() {
        chooseRootPath(for: .claude)
    }

    @objc private func chooseCodexRootPath() {
        chooseRootPath(for: .codex)
    }

    private func chooseRootPath(for tool: SourceTool) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose \(tool.rawValue) root"
        panel.message = "Select the root folder used for \(tool.rawValue) sessions."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            guard result == .OK, let selectedPath = panel.url?.path else {
                return
            }

            switch tool {
            case .claude:
                sourceDraft.claude.mode = .custom
                sourceDraft.claude.customRoot = selectedPath
            case .codex:
                sourceDraft.codex.mode = .custom
                sourceDraft.codex.customRoot = selectedPath
            }

            statusMessage = ""
            loadControls()
        }
    }

    @objc private func applySourceChanges() {
        let stagedSettings = stagedSourceSettings()
        let resolution = sessionSourceLocator.resolve(for: stagedSettings)
        guard sourceDraft.isDirty(comparedTo: settings), sourceWarningMessage(for: resolution) == nil else {
            statusMessage = "Choose valid source settings before applying."
            loadControls()
            return
        }

        let fallbackTools = sourceDraft.toolsUsingAutomaticFallback(for: resolution)
        let normalizedDraft = sourceDraft.normalized(for: resolution)

        settings.sessionSourceConfiguration = normalizedDraft.sessionSourceConfiguration
        sourceDraft = PreferencesSourceDraft(settings: settings)
        saveSettings(status: sourceAppliedStatusMessage(for: fallbackTools))
    }

    private func sourceAppliedStatusMessage(for fallbackTools: [String]) -> String {
        guard fallbackTools.isEmpty == false else {
            return "Source settings applied"
        }

        let toolSummary: String
        if fallbackTools.count == 2 {
            toolSummary = "Claude and Codex"
        } else {
            toolSummary = fallbackTools[0]
        }

        return "Source settings applied with automatic fallback for \(toolSummary)."
    }

    @objc private func changeShortcutAction() {
        guard let window, shortcutCaptureWindowController == nil else { return }

        let controller = ShortcutCaptureWindowController(currentBinding: settings.hotkeyBinding) { [weak self] binding in
            guard let self else { return }
            settings.hotkeyKeyCode = binding.keyCode
            settings.hotkeyModifiers = binding.modifiers
            saveSettings(status: "Shortcut updated")
        }

        shortcutCaptureWindowController = controller
        controller.presentSheet(for: window) { [weak self] in
            self?.shortcutCaptureWindowController = nil
        }
    }

    @objc private func resetShortcutAction() {
        settings.hotkeyKeyCode = HotkeyBinding.default.keyCode
        settings.hotkeyModifiers = HotkeyBinding.default.modifiers
        saveSettings(status: "Shortcut reset to default")
    }

    @objc private func reindexAction() {
        onReindex()
        statusMessage = "Reindex started"
        loadControls()
    }

    @objc private func exportDiagnosticsAction() {
        onExportDiagnostics()
        statusMessage = "Diagnostics exported"
        loadControls()
    }

    private var selectedTheme: AppTheme {
        switch themePopup.titleOfSelectedItem ?? "System" {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
            return .system
        }
    }

    private func selectedThemeLabel(for theme: AppTheme) -> String {
        switch theme {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    private var bundleShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Dev Build"
    }

    private var bundleBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    #if DEBUG
    var settingsStoreForTesting: SettingsStore {
        settingsStore
    }

    func updateSourceDraftForTesting(_ update: (inout PreferencesSourceDraft) -> Void) {
        update(&sourceDraft)
        statusMessage = ""
        loadControls()
    }
    #endif
}
