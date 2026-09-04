import Cocoa

/// A headline figure: small title, large value, one-line subtitle carrying the comparison.
/// Uses semantic text colors only, so appearance changes need no extra handling.
final class StatTileView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        valueLabel.textColor = .labelColor

        // The comparison can run long ("+1h 20m vs usual Wednesday"), so allow a second line.
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.cell?.wraps = true
        subtitleLabel.cell?.truncatesLastVisibleLine = true

        for label in [titleLabel, valueLabel, subtitleLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [titleLabel, valueLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        // A wrapping label needs to know its width before it can report a two-line height.
        subtitleLabel.preferredMaxLayoutWidth = bounds.width
        super.layout()
    }

    func update(value: String, subtitle: String) {
        valueLabel.stringValue = value
        subtitleLabel.stringValue = subtitle
    }
}
