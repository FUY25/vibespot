import AppKit

final class ResultRowView: NSTableCellView {
    static let rowHeightWithoutActivity: CGFloat = 54
    static let rowHeightWithActivity: CGFloat = 72

    private let toolIcon = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let statusTextLabel = NSTextField(labelWithString: "")
    private let activityLabel = NSTextField(labelWithString: "")

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
        toolIcon.image = ToolIcon.image(for: result.tool, size: 18)
        titleLabel.stringValue = result.title
        metadataLabel.stringValue = makeMetadataText(for: result)
        statusTextLabel.stringValue = makeStatusText(for: result)

        if let activityPreview = result.activityPreview, result.activityStatus != .closed {
            activityLabel.stringValue = activityPreview.text
            activityLabel.isHidden = false
            applyActivityStyle(for: activityPreview)
        } else {
            activityLabel.stringValue = ""
            activityLabel.isHidden = true
        }

        updateTextColors()
    }

    static func height(for result: SearchResult) -> CGFloat {
        result.activityStatus == .closed ? rowHeightWithoutActivity : rowHeightWithActivity
    }

    private func configure() {
        identifier = NSUserInterfaceItemIdentifier("ResultRowView")
        translatesAutoresizingMaskIntoConstraints = false

        toolIcon.translatesAutoresizingMaskIntoConstraints = false
        toolIcon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metadataLabel.font = .systemFont(ofSize: 11, weight: .regular)
        metadataLabel.lineBreakMode = .byTruncatingTail

        statusTextLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        statusTextLabel.alignment = .right
        statusTextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        activityLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        activityLabel.lineBreakMode = .byTruncatingTail
        activityLabel.maximumNumberOfLines = 1

        let titleRow = NSStackView(views: [toolIcon, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 9

        let headerRow = NSStackView(views: [titleRow, statusTextLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill

        let bodyStack = NSStackView(views: [headerRow, metadataLabel, activityLabel])
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 2
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bodyStack)

        NSLayoutConstraint.activate([
            toolIcon.widthAnchor.constraint(equalToConstant: 18),
            toolIcon.heightAnchor.constraint(equalToConstant: 18),
            headerRow.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyStack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            bodyStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
        ])

        updateTextColors()
    }

    private func makeMetadataText(for result: SearchResult) -> String {
        let time = RelativeTimeFormatter.string(from: result.lastActivityAt)
        let projectName = result.projectName.isEmpty
            ? URL(fileURLWithPath: result.project).lastPathComponent
            : result.projectName
        let branch = result.gitBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenCount = formatTokenCount(result.tokenCount)

        var parts = [time]

        if !projectName.isEmpty {
            let projectPart = branch.isEmpty ? projectName : "\(projectName) / \(branch)"
            parts.append(projectPart)
        }

        if result.tokenCount > 0 {
            parts.append(tokenCount)
        }

        return parts.joined(separator: " · ")
    }

    private func makeStatusText(for result: SearchResult) -> String {
        switch result.activityStatus {
        case .working:
            return "Working"
        case .waiting:
            return "Awaiting input"
        case .closed:
            return RelativeTimeFormatter.string(from: result.lastActivityAt)
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk tokens", Double(count) / 1000.0)
        }

        return "\(count) tokens"
    }

    private func updateTextColors() {
        let emphasized = backgroundStyle == .emphasized
        titleLabel.textColor = emphasized ? .white : .labelColor
        metadataLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .secondaryLabelColor
        statusTextLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .tertiaryLabelColor
        toolIcon.alphaValue = emphasized ? 1.0 : 0.96
    }

    private func applyActivityStyle(for activityPreview: ActivityPreview) {
        switch activityPreview.kind {
        case .tool, .fileEdit:
            activityLabel.textColor = NSColor(red: 0.54, green: 0.70, blue: 0.97, alpha: 1.0)
            activityLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        case .assistant:
            activityLabel.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.72)
            let italicDescriptor = NSFont.systemFont(ofSize: 10.5).fontDescriptor.withSymbolicTraits(.italic)
            if let italicFont = NSFont(descriptor: italicDescriptor, size: 10.5) {
                activityLabel.font = italicFont
            } else {
                activityLabel.font = .systemFont(ofSize: 10.5)
            }
        }
    }
}
