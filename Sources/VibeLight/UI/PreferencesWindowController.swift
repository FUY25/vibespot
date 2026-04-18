import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let launchAtLoginSupported: Bool
    private let onApplySettings: @MainActor @Sendable (AppSettings) -> Void
    private let onReindex: @MainActor @Sendable () -> Void
    private let onExportDiagnostics: @MainActor @Sendable () -> Void
    private var settings: AppSettings

    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginToggle = NSSwitch(frame: .zero)
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        settingsStore: SettingsStore,
        launchAtLoginSupported: Bool = LaunchAtLoginManager().isSupportedRuntime,
        onApplySettings: @escaping @MainActor @Sendable (AppSettings) -> Void,
        onReindex: @escaping @MainActor @Sendable () -> Void,
        onExportDiagnostics: @escaping @MainActor @Sendable () -> Void
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginSupported = launchAtLoginSupported
        self.onApplySettings = onApplySettings
        self.onReindex = onReindex
        self.onExportDiagnostics = onExportDiagnostics
        self.settings = settingsStore.load()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)

        configureWindow()
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

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let splitContainer = NSStackView()
        splitContainer.translatesAutoresizingMaskIntoConstraints = false
        splitContainer.orientation = .horizontal
        splitContainer.spacing = 0
        splitContainer.alignment = .top

        let sidebar = makeSidebar()
        let main = makeMainContent()

        splitContainer.addArrangedSubview(sidebar)
        splitContainer.addArrangedSubview(main)

        contentView.addSubview(splitContainer)
        NSLayoutConstraint.activate([
            splitContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.state = .active

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18

        let appName = NSTextField(labelWithString: "Flare")
        appName.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "Native search for Claude Code and Codex")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [appName, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4

        let generalItem = makeSidebarItem(title: "General", symbolName: "gearshape.fill", selected: true)
        let aboutItem = makeSidebarItem(title: "About", symbolName: "sparkles", selected: false)
        aboutItem.alphaValue = 0.55

        let items = NSStackView(views: [generalItem, aboutItem])
        items.orientation = .vertical
        items.alignment = .leading
        items.spacing = 8

        root.addArrangedSubview(titleStack)
        root.addArrangedSubview(items)

        sidebar.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 28),
        ])

        return sidebar
    }

    private func makeSidebarItem(title: String, symbolName: String, selected: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 11
        container.layer?.backgroundColor = (selected ? NSColor.controlAccentColor : .clear).cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) {
            icon.image = image
        }
        icon.contentTintColor = selected ? .white : .secondaryLabelColor

        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        label.textColor = selected ? .white : .labelColor

        container.addSubview(icon)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 176),
            container.heightAnchor.constraint(equalToConstant: 34),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func makeMainContent() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 24

        let title = NSTextField(labelWithString: "General")
        title.font = NSFont.systemFont(ofSize: 28, weight: .semibold)

        let systemCard = makeSectionCard(
            title: "System",
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
            ]
        )

        let actionsCard = makeSectionCard(
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

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        root.addArrangedSubview(title)
        root.addArrangedSubview(systemCard)
        root.addArrangedSubview(actionsCard)
        root.addArrangedSubview(statusLabel)

        documentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 28),
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28),
            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -56),
        ])

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(launchAtLoginChanged)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)

        return scrollView
    }

    private func makeSectionCard(title: String, rows: [NSView]) -> NSView {
        let card = NSVisualEffectView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .popover
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0

        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        let rowsStack = NSStackView()
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0

        for (index, row) in rows.enumerated() {
            rowsStack.addArrangedSubview(row)
            if index < rows.count - 1 {
                rowsStack.addArrangedSubview(makeSeparator())
            }
        }

        root.addArrangedSubview(heading)
        root.addArrangedSubview(rowsStack)
        root.setCustomSpacing(14, after: heading)

        card.addSubview(root)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 540),
            root.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        return card
    }

    private func makeToggleRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 504),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
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
            title: "Display",
            subtitle: "Match the system or pin Flare to a single appearance.",
            control: themePopup
        )
    }

    private func makeShortcutRow() -> NSView {
        shortcutValueLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        shortcutValueLabel.alignment = .center
        shortcutValueLabel.wantsLayer = true
        shortcutValueLabel.layer?.cornerRadius = 9
        shortcutValueLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        shortcutValueLabel.textColor = .controlAccentColor
        shortcutValueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shortcutValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),
            shortcutValueLabel.heightAnchor.constraint(equalToConstant: 30),
        ])

        let changeButton = NSButton(title: "Change Shortcut", target: self, action: #selector(changeShortcutAction))
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetShortcutAction))
        resetButton.bezelStyle = .recessed

        let buttons = NSStackView(views: [changeButton, resetButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let trailing = NSStackView(views: [shortcutValueLabel, buttons])
        trailing.orientation = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 8

        return makeTrailingControlRow(
            title: "Shortcut",
            subtitle: "Choose the global shortcut that opens Flare anywhere.",
            control: trailing
        )
    }

    private func makeActionRow(title: String, subtitle: String, buttonTitle: String, action: Selector) -> NSView {
        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded
        return makeTrailingControlRow(title: title, subtitle: subtitle, control: button)
    }

    private func makeTrailingControlRow(title: String, subtitle: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        control.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 504),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
        ])

        return row
    }

    private func makeSeparator() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 504),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return line
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
        statusLabel.stringValue = launchAtLoginSupported
            ? "Changes are saved locally."
            : "Launch at login is only available from a packaged app build."
    }

    private func saveSettings(status: String) {
        settingsStore.save(settings)
        onApplySettings(settings)
        shortcutValueLabel.stringValue = settings.hotkeyBinding.displayString
        statusLabel.stringValue = status
    }

    @objc private func launchAtLoginChanged() {
        guard launchAtLoginSupported else { return }
        settings.launchAtLogin = launchAtLoginToggle.state == .on
        saveSettings(status: "Launch setting updated")
    }

    @objc private func themeChanged() {
        settings.theme = selectedTheme
        saveSettings(status: "Appearance updated")
    }

    @objc private func changeShortcutAction() {
        guard let window else { return }
        let controller = ShortcutCaptureWindowController(currentBinding: settings.hotkeyBinding) { [weak self] binding in
            guard let self else { return }
            self.settings.hotkeyKeyCode = binding.keyCode
            self.settings.hotkeyModifiers = binding.modifiers
            self.saveSettings(status: "Shortcut updated")
        }
        controller.presentSheet(for: window)
    }

    @objc private func resetShortcutAction() {
        settings.hotkeyKeyCode = HotkeyBinding.default.keyCode
        settings.hotkeyModifiers = HotkeyBinding.default.modifiers
        saveSettings(status: "Shortcut reset to default")
    }

    @objc private func reindexAction() {
        onReindex()
        statusLabel.stringValue = "Reindex started"
    }

    @objc private func exportDiagnosticsAction() {
        onExportDiagnostics()
        statusLabel.stringValue = "Diagnostics exported"
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
}
