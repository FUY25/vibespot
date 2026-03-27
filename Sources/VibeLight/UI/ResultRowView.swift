import AppKit

final class ResultRowView: NSTableCellView {
    static let rowHeightWithoutActivity: CGFloat = DesignTokens.Spacing.rowHeightClosed   // 56
    static let rowHeightWithActivity: CGFloat = DesignTokens.Spacing.rowHeightActive      // 74

    private let toolIcon = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let statusTextLabel = NSTextField(labelWithString: "")
    private let activityLabel = NSTextField(labelWithString: "")
    private let typingDotsView = NSStackView()

    private var currentActivityStatus: SessionActivityStatus = .closed
    private var currentActivityPreview: ActivityPreview?

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
        toolIcon.image = ToolIcon.image(for: result.tool, size: DesignTokens.Spacing.toolIconSize)
        titleLabel.stringValue = result.title
        metadataLabel.stringValue = makeMetadataText(for: result)
        statusTextLabel.stringValue = makeStatusText(for: result)
        currentActivityStatus = result.activityStatus
        currentActivityPreview = result.activityPreview

        if let activityPreview = result.activityPreview, result.activityStatus != .closed {
            activityLabel.stringValue = activityPreview.text
            activityLabel.isHidden = false
            applyActivityStyle(for: activityPreview)
        } else {
            activityLabel.stringValue = ""
            activityLabel.isHidden = true
        }

        resetStateAppearance()
        updateTextColors()
        applyActivityState(result.activityStatus)
    }

    static func height(for result: SearchResult) -> CGFloat {
        result.activityStatus == .closed ? rowHeightWithoutActivity : rowHeightWithActivity
    }

    private func configure() {
        identifier = NSUserInterfaceItemIdentifier("ResultRowView")
        translatesAutoresizingMaskIntoConstraints = false

        toolIcon.translatesAutoresizingMaskIntoConstraints = false
        toolIcon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = DesignTokens.Font.sessionTitle
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metadataLabel.font = DesignTokens.Font.metadata
        metadataLabel.lineBreakMode = .byTruncatingTail

        statusTextLabel.font = DesignTokens.Font.statusLabel
        statusTextLabel.alignment = .right
        statusTextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusTextLabel.wantsLayer = true

        activityLabel.font = DesignTokens.Font.activity
        activityLabel.lineBreakMode = .byTruncatingTail
        activityLabel.maximumNumberOfLines = 1

        titleLabel.wantsLayer = true

        configureTypingDots()

        let titleRow = NSStackView(views: [toolIcon, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = DesignTokens.Spacing.logoToTextGap

        let statusContainer = NSStackView(views: [statusTextLabel, typingDotsView])
        statusContainer.orientation = .horizontal
        statusContainer.alignment = .centerY
        statusContainer.spacing = 6

        let headerRow = NSStackView(views: [titleRow, statusContainer])
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
            toolIcon.widthAnchor.constraint(equalToConstant: DesignTokens.Spacing.toolIconSize),
            toolIcon.heightAnchor.constraint(equalToConstant: DesignTokens.Spacing.toolIconSize),
            headerRow.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.rowHorizontalPadding),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.rowHorizontalPadding),
            bodyStack.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.rowVerticalPadding),
            bodyStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -DesignTokens.Spacing.rowVerticalPadding),
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
            return "WORKING"
        case .waiting:
            return "AWAITING"
        case .closed:
            return ""
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
        let titleAlpha = currentActivityStatus == .closed ? DesignTokens.Color.closedTitleAlpha : 1.0
        let iconAlpha = currentActivityStatus == .closed ? DesignTokens.Color.closedTitleAlpha : (emphasized ? 1.0 : 0.96)

        titleLabel.textColor = emphasized ? .white : .labelColor
        titleLabel.alphaValue = titleAlpha
        metadataLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .secondaryLabelColor
        if currentActivityStatus == .waiting {
            statusTextLabel.textColor = DesignTokens.Color.waitingAmber
        } else {
            statusTextLabel.textColor = emphasized ? NSColor.white.withAlphaComponent(0.82) : .tertiaryLabelColor
        }
        toolIcon.alphaValue = iconAlpha
    }

    private func applyActivityStyle(for activityPreview: ActivityPreview) {
        switch activityPreview.kind {
        case .tool, .fileEdit:
            activityLabel.textColor = DesignTokens.Color.activityCyan
            activityLabel.font = DesignTokens.Font.activity
        case .assistant:
            activityLabel.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
            let activitySize = DesignTokens.Font.activity.pointSize
            let italicDescriptor = NSFont.systemFont(ofSize: activitySize).fontDescriptor.withSymbolicTraits(.italic)
            if let italicFont = NSFont(descriptor: italicDescriptor, size: activitySize) {
                activityLabel.font = italicFont
            } else {
                activityLabel.font = .systemFont(ofSize: activitySize)
            }
        }
    }

    private func applyActivityState(_ state: SessionActivityStatus) {
        switch state {
        case .working:
            statusTextLabel.isHidden = true
            typingDotsView.isHidden = false
            applyShimmer()
            startTypingDots()
        case .waiting:
            statusTextLabel.isHidden = false
            typingDotsView.isHidden = true
            applyWaitingBreathing()
        case .closed:
            statusTextLabel.isHidden = true
            typingDotsView.isHidden = true
        }
    }

    private func resetStateAppearance() {
        titleLabel.layer?.mask = nil
        titleLabel.layer?.removeAllAnimations()
        statusTextLabel.layer?.removeAllAnimations()
        statusTextLabel.alphaValue = 1.0
        typingDotsView.isHidden = true
        statusTextLabel.isHidden = false

        for dot in typingDotsView.arrangedSubviews {
            dot.layer?.removeAllAnimations()
        }
    }

    private func configureTypingDots() {
        typingDotsView.orientation = .horizontal
        typingDotsView.alignment = .centerY
        typingDotsView.spacing = 3
        typingDotsView.translatesAutoresizingMaskIntoConstraints = false
        typingDotsView.isHidden = true

        for _ in 0..<3 {
            let dotSize = DesignTokens.Animation.typingDotSize
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: dotSize, height: dotSize))
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: dotSize),
                dot.heightAnchor.constraint(equalToConstant: dotSize),
            ])
            typingDotsView.addArrangedSubview(dot)
        }
    }

    private func startTypingDots() {
        for (index, dot) in typingDotsView.arrangedSubviews.enumerated() {
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0, DesignTokens.Animation.typingDotBounce, 0]
            bounce.keyTimes = [0, 0.3, 0.6]
            bounce.duration = DesignTokens.Animation.typingDotDuration
            bounce.repeatCount = .infinity
            bounce.beginTime = CACurrentMediaTime() + Double(index) * DesignTokens.Animation.typingDotStagger
            dot.layer?.add(bounce, forKey: "bounce")
        }
    }

    private func applyWaitingBreathing() {
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = DesignTokens.Animation.breathingFromOpacity
        breathe.toValue = DesignTokens.Animation.breathingToOpacity
        breathe.duration = DesignTokens.Animation.breathingDuration
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusTextLabel.layer?.add(breathe, forKey: "breathe")
    }

    private func applyShimmer() {
        titleLabel.layoutSubtreeIfNeeded()
        guard let titleLayer = titleLabel.layer else {
            return
        }

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.labelColor.cgColor,
            DesignTokens.Color.workingBlue.cgColor,
            NSColor.labelColor.cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = titleLayer.bounds

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.3, -0.15, 0.0]
        animation.toValue = [1.0, 1.15, 1.3]
        animation.duration = DesignTokens.Animation.shimmerDuration
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "shimmer")

        titleLayer.mask = gradient
    }
}
