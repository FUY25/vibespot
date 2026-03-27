import AppKit

final class ResultRowView: NSTableCellView {
    static let rowHeightWithoutSnippet: CGFloat = 56
    static let rowHeightWithSnippet: CGFloat = 78

    private let toolIcon = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateTextColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configure(with result: SearchResult) {
        toolIcon.image = ToolIcon.image(for: result.tool, size: 20)
        titleLabel.stringValue = result.title
        metadataLabel.stringValue = makeMetadataText(for: result)
        statusLabel.stringValue = Self.makeStatusText(status: result.status, startedAt: result.startedAt)
        statusDot.layer?.backgroundColor = statusColor(for: result.status).cgColor

        if let snippet = normalizedSnippet(from: result.snippet) {
            snippetLabel.stringValue = snippet
            snippetLabel.isHidden = false
        } else {
            snippetLabel.stringValue = ""
            snippetLabel.isHidden = true
        }

        updateTextColors()
    }

    static func height(for result: SearchResult) -> CGFloat {
        normalizedSnippet(from: result.snippet) == nil ? rowHeightWithoutSnippet : rowHeightWithSnippet
    }

    static func makeStatusText(
        status: String,
        startedAt: Date,
        formatter: DateFormatter? = nil
    ) -> String {
        let statusText = status == "live" ? "Live" : "Closed"
        let timestamp = (formatter ?? makeDefaultTimeFormatter()).string(from: startedAt)
        return "\(statusText) \(timestamp)"
    }

    private func configure() {
        identifier = NSUserInterfaceItemIdentifier("ResultRowView")
        translatesAutoresizingMaskIntoConstraints = false

        toolIcon.translatesAutoresizingMaskIntoConstraints = false
        toolIcon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metadataLabel.font = .systemFont(ofSize: 12, weight: .regular)
        metadataLabel.lineBreakMode = .byTruncatingTail

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4

        snippetLabel.font = .systemFont(ofSize: 12, weight: .regular)
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 1

        let titleRow = NSStackView(views: [toolIcon, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let statusStack = NSStackView(views: [statusDot, statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 6

        let headerRow = NSStackView(views: [titleRow, statusStack])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill

        let bodyStack = NSStackView(views: [headerRow, metadataLabel, snippetLabel])
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 4
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bodyStack)

        NSLayoutConstraint.activate([
            toolIcon.widthAnchor.constraint(equalToConstant: 20),
            toolIcon.heightAnchor.constraint(equalToConstant: 20),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            headerRow.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bodyStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bodyStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])

        updateTextColors()
    }

    private func makeMetadataText(for result: SearchResult) -> String {
        let projectName = result.projectName.isEmpty
            ? URL(fileURLWithPath: result.project).lastPathComponent
            : result.projectName
        let branch = result.gitBranch.trimmingCharacters(in: .whitespacesAndNewlines)

        if branch.isEmpty {
            return projectName
        }

        return "\(projectName) / \(branch)"
    }

    private func statusColor(for status: String) -> NSColor {
        status == "live" ? NSColor.systemGreen : NSColor.systemGray
    }

    private static func makeDefaultTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func updateTextColors() {
        let emphasized = backgroundStyle == .emphasized
        titleLabel.textColor = emphasized ? .white : .labelColor
        metadataLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .secondaryLabelColor
        statusLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .tertiaryLabelColor
        snippetLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.9) : .secondaryLabelColor
        toolIcon.alphaValue = emphasized ? 1.0 : 0.96
    }

    private static func normalizedSnippet(from snippet: String?) -> String? {
        guard let snippet else {
            return nil
        }

        let cleaned = snippet
            .replacingOccurrences(of: ">>>", with: "")
            .replacingOccurrences(of: "<<<", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private func normalizedSnippet(from snippet: String?) -> String? {
        Self.normalizedSnippet(from: snippet)
    }
}
