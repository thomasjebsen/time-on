import Cocoa

final class PreferencesWindowController: NSWindowController {
    private let sessionManager: SessionManager
    private var previewLabel: NSTextField!
    private var customField: NSTextField!
    private var indicatorButtons: [NSButton] = []

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Time On Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // — Timer section —
        addLabel("Timer", weight: .bold, size: 13, to: stackView)

        let reminderCheck = NSButton(checkboxWithTitle: "Enable break reminders", target: self, action: #selector(toggleReminder(_:)))
        reminderCheck.state = Preferences.reminderEnabled ? .on : .off
        stackView.addArrangedSubview(reminderCheck)

        stackView.addArrangedSubview(makeRow("Remind every:", fieldValue: "\(Preferences.reminderIntervalMinutes)", tag: 1, suffix: "minutes"))
        stackView.addArrangedSubview(makeRow("Idle after:", fieldValue: "\(Preferences.idleThresholdMinutes)", tag: 2, suffix: "minutes of inactivity"))

        let secondsCheck = NSButton(checkboxWithTitle: "Show seconds in timer", target: self, action: #selector(toggleSeconds(_:)))
        secondsCheck.state = Preferences.showSeconds ? .on : .off
        stackView.addArrangedSubview(secondsCheck)

        addSeparator(to: stackView)

        // — Stay Awake section —
        addLabel("Stay Awake", weight: .bold, size: 13, to: stackView)

        stackView.addArrangedSubview(makeRow("Default duration:", fieldValue: "\(Preferences.defaultAwakeDurationMinutes)", tag: 3, suffix: "minutes"))

        addLabel("Indicator style:", weight: .medium, size: 12, to: stackView)

        // Preset buttons
        let presetsRow = NSStackView()
        presetsRow.orientation = .horizontal
        presetsRow.spacing = 4

        for (index, preset) in Preferences.indicatorPresets.enumerated() {
            let btn = NSButton(title: preset.symbol, target: self, action: #selector(selectPreset(_:)))
            btn.tag = index
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 15)
            btn.toolTip = preset.label
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
            btn.state = (index == Preferences.awakeIndicatorIndex) ? .on : .off
            indicatorButtons.append(btn)
            presetsRow.addArrangedSubview(btn)
        }
        stackView.addArrangedSubview(presetsRow)

        // Custom emoji field
        let customRow = NSStackView()
        customRow.orientation = .horizontal
        customRow.spacing = 8
        customRow.addArrangedSubview(NSTextField(labelWithString: "Custom:"))
        customField = NSTextField(string: Preferences.customAwakeIndicator)
        customField.placeholderString = "Enter emoji..."
        customField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        customField.tag = 10
        customField.delegate = self
        customRow.addArrangedSubview(customField)

        let useCustomBtn = NSButton(title: "Use", target: self, action: #selector(useCustomIndicator))
        useCustomBtn.bezelStyle = .rounded
        customRow.addArrangedSubview(useCustomBtn)

        stackView.addArrangedSubview(customRow)

        // Preview
        previewLabel = NSTextField(labelWithString: "Preview: 25m \(Preferences.awakeIndicator)")
        previewLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        stackView.addArrangedSubview(previewLabel)

        addSeparator(to: stackView)

        // — General section —
        addLabel("General", weight: .bold, size: 13, to: stackView)

        let launchCheck = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheck.state = LaunchAtLoginManager.isEnabled ? .on : .off
        stackView.addArrangedSubview(launchCheck)

        addSeparator(to: stackView)

        // Info
        let info = NSTextField(wrappingLabelWithString: "Left-click the timer to toggle Stay Awake. Right-click for the full menu.")
        info.textColor = .secondaryLabelColor
        info.font = .systemFont(ofSize: 11)
        stackView.addArrangedSubview(info)
    }

    // MARK: - Helpers

    private func addLabel(_ text: String, weight: NSFont.Weight, size: CGFloat, to stack: NSStackView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        stack.addArrangedSubview(label)
    }

    private func addSeparator(to stack: NSStackView) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    private func makeRow(_ label: String, fieldValue: String, tag: Int, suffix: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(NSTextField(labelWithString: label))
        let field = NSTextField(string: fieldValue)
        field.tag = tag
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 50).isActive = true
        row.addArrangedSubview(field)
        row.addArrangedSubview(NSTextField(labelWithString: suffix))
        return row
    }

    private func updatePreview() {
        previewLabel?.stringValue = "Preview: 25m \(Preferences.awakeIndicator)"
    }

    private func deselectAllPresets() {
        for btn in indicatorButtons { btn.state = .off }
    }

    // MARK: - Actions

    @objc private func toggleReminder(_ sender: NSButton) {
        Preferences.reminderEnabled = sender.state == .on
    }

    @objc private func toggleSeconds(_ sender: NSButton) {
        Preferences.showSeconds = sender.state == .on
    }

    @objc private func selectPreset(_ sender: NSButton) {
        deselectAllPresets()
        sender.state = .on
        Preferences.awakeIndicatorIndex = sender.tag
        updatePreview()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLoginManager.setEnabled(sender.state == .on)
    }

    @objc private func useCustomIndicator() {
        let value = customField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        Preferences.customAwakeIndicator = value
        Preferences.awakeIndicatorIndex = -1
        deselectAllPresets()
        updatePreview()
    }
}

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        switch field.tag {
        case 1:
            Preferences.reminderIntervalMinutes = max(1, field.integerValue)
        case 2:
            Preferences.idleThresholdMinutes = max(1, field.integerValue)
        case 3:
            Preferences.defaultAwakeDurationMinutes = max(1, field.integerValue)
        default:
            break
        }
    }
}
