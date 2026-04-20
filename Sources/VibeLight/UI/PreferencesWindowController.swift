import AppKit

private enum SourceTool: String {
    case claude = "Claude"
    case codex = "Codex"
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private enum StatusTone {
        case normal
        case error
    }

    private let settingsStore: SettingsStore
    private let launchAtLoginSupported: Bool
    private let sessionSourceLocator: SessionSourceLocator
    private let onApplySettings: @MainActor @Sendable (AppSettings) -> String?
    private let onReindex: @MainActor @Sendable () -> Void
    private let onExportDiagnostics: @MainActor @Sendable () -> String?

    private var settings: AppSettings
    private var sourceDraft: PreferencesSourceDraft
    private var statusMessage: String = ""
    private var statusTone: StatusTone = .normal

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

    private let windowWidth: CGFloat = 534
    private let windowHeight: CGFloat = 508

    init(
        settingsStore: SettingsStore,
        launchAtLoginSupported: Bool = LaunchAtLoginManager().isSupportedRuntime,
        sessionSourceLocator: SessionSourceLocator = SessionSourceLocator(),
        onApplySettings: @escaping @MainActor @Sendable (AppSettings) -> String?,
        onReindex: @escaping @MainActor @Sendable () -> Void,
        onExportDiagnostics: @escaping @MainActor @Sendable () -> String?
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 460)
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
        clearStatus()
        loadControls()
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

    func presentStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusTone = isError ? .error : .normal
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
        contentStack.spacing = 14

        documentView.addSubview(contentStack)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -36),
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
            makeSystemSection(),
            makeSourceSection(),
            makeMaintenanceSection(),
            makeAboutSection(),
            makeStatusView(),
        ]

        views.forEach { view in
            contentStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
    }
    private func makeSystemSection() -> NSView {
        makeSectionCard(
            title: "System",
            rows: [
                makeToggleRow(
                    title: "Launch at login",
                    subtitle: launchAtLoginSupported
                        ? "Open VibeSpot automatically when you sign in."
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
        sourceWarningLabel.maximumNumberOfLines = 2
        sourceWarningLabel.isHidden = true

        sourceApplyButton.bezelStyle = .rounded

        let footnote = makeFootnote("Source edits stay local in this window until you click Apply.")
        let sourceStack = makeSeparatedContentStack(views: [
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
        ], separatorFromIndex: 1)
        sourceStack.arrangedSubviews.forEach { view in
            view.widthAnchor.constraint(equalTo: sourceStack.widthAnchor).isActive = true
        }

        return makeSectionCard(
            title: "Session Sources",
            customBody: sourceStack
        )
    }

    private func makeMaintenanceSection() -> NSView {
        makeSectionCard(
            title: "Maintenance",
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
            title: "About",
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
            row.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true
            if index < rows.count - 1 {
                let separator = makeSeparator()
                bodyStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true
            }
        }

        return makeSectionCard(title: title, customBody: bodyStack)
    }

    private func makeSectionCard(title: String, customBody: NSView) -> NSView {
        let group = NSView()
        group.translatesAutoresizingMaskIntoConstraints = false
        let heading = makeSectionLabel(title)
        let stack = NSStackView(views: [heading, customBody])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9

        group.addSubview(stack)
        NSLayoutConstraint.activate([
            customBody.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor),
        ])
        return group
    }

    private func makeSeparatedContentStack(
        views: [NSView],
        separatorFromIndex: Int = 0
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        views.enumerated().forEach { index, view in
            stack.addArrangedSubview(view)
            if index > 0 {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            if index >= separatorFromIndex, index < views.count - 1 {
                let separator = makeSeparator()
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        return stack
    }

    private func makeToggleRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = makeBaseRow()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

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
            subtitle: "Match the system or pin VibeSpot to a single appearance.",
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
            subtitle: "Choose the global shortcut that opens VibeSpot anywhere.",
            control: trailing
        )
    }

    private func styleShortcutValueLabel() {
        shortcutValueLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        shortcutValueLabel.alignment = .center
        shortcutValueLabel.wantsLayer = true
        shortcutValueLabel.layer?.cornerRadius = 6
        shortcutValueLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        shortcutValueLabel.textColor = .labelColor
        shortcutValueLabel.translatesAutoresizingMaskIntoConstraints = false
        if shortcutValueLabel.constraints.isEmpty {
            NSLayoutConstraint.activate([
                shortcutValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 114),
                shortcutValueLabel.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
        shortcutValueLabel.alphaValue = 0.88
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

        let heading = makeSubsectionLabel(title)
        let stack = makeSeparatedContentStack(views: [
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
        ], separatorFromIndex: 1)

        stack.arrangedSubviews.dropFirst().forEach { view in
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

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
        subtitleLabel.maximumNumberOfLines = 2
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
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
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
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.16).cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeKickerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSubsectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
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
        claudeRootPathButton.alphaValue = sourceDraft.claude.mode == .custom ? 1 : 0.72
        codexRootPathButton.isEnabled = sourceDraft.codex.mode == .custom
        codexRootPathButton.alphaValue = sourceDraft.codex.mode == .custom ? 1 : 0.72

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
        statusLabel.textColor = statusTone == .error ? .systemRed : .secondaryLabelColor
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
        if let errorMessage = onApplySettings(settings) {
            presentStatus(errorMessage, isError: true)
            return
        }
        statusMessage = status
        statusTone = .normal
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
        clearStatus()
        loadControls()
    }

    @objc private func codexSourceModeChanged() {
        sourceDraft.codex.mode = codexSourceModePopup.titleOfSelectedItem == "Custom" ? .custom : .automatic
        clearStatus()
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

            clearStatus()
            loadControls()
        }
    }

    @objc private func applySourceChanges() {
        let stagedSettings = stagedSourceSettings()
        let resolution = sessionSourceLocator.resolve(for: stagedSettings)
        guard sourceDraft.isDirty(comparedTo: settings), sourceWarningMessage(for: resolution) == nil else {
            presentStatus("Choose valid source settings before applying.", isError: true)
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
        if let errorMessage = onExportDiagnostics() {
            presentStatus(errorMessage, isError: true)
            return
        }
        statusMessage = "Diagnostics exported"
        statusTone = .normal
        loadControls()
    }

    private func clearStatus() {
        statusMessage = ""
        statusTone = .normal
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
        clearStatus()
        loadControls()
    }

    var currentStatusMessageForTesting: String {
        statusLabel.stringValue
    }
    #endif
}
