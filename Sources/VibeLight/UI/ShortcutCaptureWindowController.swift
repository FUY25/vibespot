import AppKit

@MainActor
final class ShortcutCaptureWindowController: NSWindowController, NSWindowDelegate {
    private let onSave: @MainActor @Sendable (HotkeyBinding) -> Void
    private let currentBinding: HotkeyBinding
    private let instructionLabel = NSTextField(labelWithString: "")
    private let currentValueLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private var captureView: ShortcutCaptureView?
    private var onClose: (@MainActor @Sendable () -> Void)?
    private var isClosing = false

    init(
        currentBinding: HotkeyBinding,
        onSave: @escaping @MainActor @Sendable (HotkeyBinding) -> Void
    ) {
        self.currentBinding = currentBinding
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Change Shortcut"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentSheet(for parentWindow: NSWindow, onClose: (@MainActor @Sendable () -> Void)? = nil) {
        self.onClose = onClose
        parentWindow.beginSheet(window!) { [weak self] _ in
            self?.onClose?()
            self?.onClose = nil
            self?.close()
        }
        window?.makeFirstResponder(captureView)
    }

    private func configureWindow() {
        guard let window, let contentView = window.contentView else { return }
        window.delegate = self
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12

        let titleLabel = NSTextField(labelWithString: "Press your new shortcut")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        instructionLabel.stringValue = "Use Command, Option, Shift, or Control with another key."
        instructionLabel.textColor = .secondaryLabelColor

        currentValueLabel.stringValue = "Current: \(currentBinding.displayString)"
        currentValueLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

        errorLabel.stringValue = ""
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        let captureView = ShortcutCaptureView(
            onCapture: { [weak self] binding in
            self?.handleCapture(binding: binding)
            },
            onCancel: { [weak self] in
                self?.closeSheet()
            }
        )
        captureView.translatesAutoresizingMaskIntoConstraints = false
        captureView.wantsLayer = true
        captureView.layer?.cornerRadius = 14
        captureView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        captureView.layer?.borderColor = NSColor.separatorColor.cgColor
        captureView.layer?.borderWidth = 1
        self.captureView = captureView

        let captureLabel = NSTextField(labelWithString: "Waiting for key press")
        captureLabel.translatesAutoresizingMaskIntoConstraints = false
        captureLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        captureLabel.textColor = .secondaryLabelColor
        captureView.addSubview(captureLabel)

        let resetButton = NSButton(title: "Reset to Default", target: self, action: #selector(resetAction))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"

        let buttonRow = NSStackView(views: [resetButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        root.addArrangedSubview(titleLabel)
        root.addArrangedSubview(instructionLabel)
        root.addArrangedSubview(currentValueLabel)
        root.addArrangedSubview(captureView)
        root.addArrangedSubview(errorLabel)
        root.addArrangedSubview(buttonRow)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),

            captureView.widthAnchor.constraint(equalTo: root.widthAnchor),
            captureView.heightAnchor.constraint(equalToConstant: 72),
            captureLabel.centerXAnchor.constraint(equalTo: captureView.centerXAnchor),
            captureLabel.centerYAnchor.constraint(equalTo: captureView.centerYAnchor),
        ])
    }

    private func handleCapture(binding: HotkeyBinding?) {
        guard let binding else {
            errorLabel.stringValue = "Use at least one modifier key."
            errorLabel.isHidden = false
            return
        }

        onSave(binding)
        closeSheet()
    }

    private func closeSheet() {
        guard let window, !isClosing else { return }
        isClosing = true
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            onClose?()
            onClose = nil
            window.orderOut(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.sheetParent != nil else { return true }
        closeSheet()
        return false
    }

    @objc private func resetAction() {
        onSave(.default)
        closeSheet()
    }

    @objc private func cancelAction() {
        closeSheet()
    }
}

private final class ShortcutCaptureView: NSView {
    private let onCapture: (HotkeyBinding?) -> Void
    private let onCancel: () -> Void

    init(
        onCapture: @escaping (HotkeyBinding?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel()
            return
        }
        onCapture(HotkeyBinding(event: event))
    }
}
