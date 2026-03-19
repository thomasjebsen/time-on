import Cocoa
import UserNotifications

final class PreferencesWindowController: NSWindowController {
    private let sessionManager: SessionManager
    private var previewLabel: NSTextField!
    private var customField: NSTextField!
    private var indicatorButtons: [NSButton] = []

    // Collapsible containers
    private var breakReminderContent: NSStackView!
    private var soundOptions: NSStackView!
    private var shakeOptions: NSStackView!
    private var shakeCustomField: NSTextField!

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        scrollView.documentView = stackView
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        // ── Timer section ──
        addLabel("Timer", weight: .bold, size: 13, to: stackView)
        stackView.addArrangedSubview(makeRow("Reset after:", fieldValue: "\(Preferences.idleThresholdMinutes)", tag: 2, suffix: "minutes of inactivity"))
        let secondsCheck = NSButton(checkboxWithTitle: "Show seconds in timer", target: self, action: #selector(toggleSeconds(_:)))
        secondsCheck.state = Preferences.showSeconds ? .on : .off
        stackView.addArrangedSubview(secondsCheck)

        addSeparator(to: stackView)

        // ── Break Reminders section ──
        addLabel("Break reminders", weight: .bold, size: 13, to: stackView)

        let reminderCheck = NSButton(checkboxWithTitle: "Enable break reminders", target: self, action: #selector(toggleReminder(_:)))
        reminderCheck.state = Preferences.reminderEnabled ? .on : .off
        stackView.addArrangedSubview(reminderCheck)

        breakReminderContent = makeCollapsibleStack()
        stackView.addArrangedSubview(breakReminderContent)

        let intervalStr = Preferences.reminderIntervalMinutes.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", Preferences.reminderIntervalMinutes)
            : String(Preferences.reminderIntervalMinutes)
        breakReminderContent.addArrangedSubview(makeRow("Remind every:", fieldValue: intervalStr, tag: 1, suffix: "minutes"))

        // Banner notification dropdown
        let bannerRow = NSStackView()
        bannerRow.orientation = .horizontal
        bannerRow.spacing = 8
        bannerRow.addArrangedSubview(NSTextField(labelWithString: "Notification:"))
        let bannerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        bannerPopup.addItem(withTitle: "Off")
        bannerPopup.addItem(withTitle: "On")
        bannerPopup.selectItem(at: Preferences.reminderBannerEnabled ? 1 : 0)
        bannerPopup.target = self
        bannerPopup.action = #selector(bannerChanged(_:))
        bannerPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        bannerRow.addArrangedSubview(bannerPopup)
        breakReminderContent.addArrangedSubview(bannerRow)

        // Sound dropdown
        let soundRow = NSStackView()
        soundRow.orientation = .horizontal
        soundRow.spacing = 8
        soundRow.addArrangedSubview(NSTextField(labelWithString: "Sound:"))
        let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        soundPopup.addItem(withTitle: "Off")
        for name in Preferences.availableSystemSounds { soundPopup.addItem(withTitle: name) }
        if Preferences.reminderSoundEnabled {
            soundPopup.selectItem(withTitle: Preferences.reminderSoundName)
        } else {
            soundPopup.selectItem(at: 0)
        }
        soundPopup.target = self
        soundPopup.action = #selector(soundSelectionChanged(_:))
        soundPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        soundRow.addArrangedSubview(soundPopup)
        let previewBtn = NSButton(title: "Play", target: self, action: #selector(previewSound))
        previewBtn.bezelStyle = .rounded
        soundRow.addArrangedSubview(previewBtn)
        breakReminderContent.addArrangedSubview(soundRow)

        soundOptions = makeCollapsibleStack()
        let volumeRow = NSStackView()
        volumeRow.orientation = .horizontal
        volumeRow.spacing = 8
        volumeRow.addArrangedSubview(NSTextField(labelWithString: "Volume:"))
        let volumeSlider = NSSlider(value: Double(Preferences.reminderSoundVolume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        volumeSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        volumeRow.addArrangedSubview(volumeSlider)
        soundOptions.addArrangedSubview(volumeRow)
        soundOptions.isHidden = !Preferences.reminderSoundEnabled
        breakReminderContent.addArrangedSubview(soundOptions)

        // Shake dropdown
        let shakeRow = NSStackView()
        shakeRow.orientation = .horizontal
        shakeRow.spacing = 8
        shakeRow.addArrangedSubview(NSTextField(labelWithString: "Shake:"))
        let shakePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let shakeItems = ["Off", "0.4s", "1s", "2s", "5s", "Until break is taken", "Custom..."]
        for item in shakeItems { shakePopup.addItem(withTitle: item) }
        selectShakePopup(shakePopup)
        shakePopup.target = self
        shakePopup.action = #selector(shakeSelectionChanged(_:))
        shakePopup.tag = 200
        shakePopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        shakeRow.addArrangedSubview(shakePopup)
        breakReminderContent.addArrangedSubview(shakeRow)

        shakeOptions = makeCollapsibleStack()
        let customShakeRow = NSStackView()
        customShakeRow.orientation = .horizontal
        customShakeRow.spacing = 8
        customShakeRow.addArrangedSubview(NSTextField(labelWithString: "Duration:"))
        shakeCustomField = NSTextField(string: String(format: "%.1f", Preferences.reminderShakeDuration))
        shakeCustomField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        shakeCustomField.tag = 5
        shakeCustomField.delegate = self
        customShakeRow.addArrangedSubview(shakeCustomField)
        customShakeRow.addArrangedSubview(NSTextField(labelWithString: "seconds"))
        shakeOptions.addArrangedSubview(customShakeRow)
        shakeOptions.isHidden = !isCustomShakeMode()
        breakReminderContent.addArrangedSubview(shakeOptions)

        // Color indicators
        let colorBeforeRow = NSStackView()
        colorBeforeRow.orientation = .horizontal
        colorBeforeRow.spacing = 8
        let colorBeforeCheck = NSButton(checkboxWithTitle: "Color before break:", target: self, action: #selector(toggleColorBefore(_:)))
        colorBeforeCheck.state = Preferences.colorBeforeBreakEnabled ? .on : .off
        colorBeforeRow.addArrangedSubview(colorBeforeCheck)
        let colorBeforeWell = NSColorWell()
        colorBeforeWell.color = NSColor(hex: Preferences.colorBeforeBreak) ?? .systemGreen
        colorBeforeWell.target = self
        colorBeforeWell.action = #selector(colorBeforeChanged(_:))
        colorBeforeWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorBeforeWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        colorBeforeRow.addArrangedSubview(colorBeforeWell)
        breakReminderContent.addArrangedSubview(colorBeforeRow)

        let colorAfterRow = NSStackView()
        colorAfterRow.orientation = .horizontal
        colorAfterRow.spacing = 8
        let colorAfterCheck = NSButton(checkboxWithTitle: "Color after break:", target: self, action: #selector(toggleColorAfter(_:)))
        colorAfterCheck.state = Preferences.colorAfterBreakEnabled ? .on : .off
        colorAfterRow.addArrangedSubview(colorAfterCheck)
        let colorAfterWell = NSColorWell()
        colorAfterWell.color = NSColor(hex: Preferences.colorAfterBreak) ?? .systemRed
        colorAfterWell.target = self
        colorAfterWell.action = #selector(colorAfterChanged(_:))
        colorAfterWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorAfterWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        colorAfterRow.addArrangedSubview(colorAfterWell)
        breakReminderContent.addArrangedSubview(colorAfterRow)

        breakReminderContent.isHidden = !Preferences.reminderEnabled

        addSeparator(to: stackView)

        // ── Stay Awake section ──
        addLabel("Stay awake", weight: .bold, size: 13, to: stackView)
        stackView.addArrangedSubview(makeRow("Default duration:", fieldValue: "\(Preferences.defaultAwakeDurationMinutes)", tag: 3, suffix: "minutes"))
        addLabel("Indicator style:", weight: .medium, size: 12, to: stackView)

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

        previewLabel = NSTextField(labelWithString: "Preview: 25m \(Preferences.awakeIndicator)")
        previewLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        stackView.addArrangedSubview(previewLabel)

        addSeparator(to: stackView)

        // ── General section ──
        addLabel("General", weight: .bold, size: 13, to: stackView)
        let launchCheck = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheck.state = LaunchAtLoginManager.isEnabled ? .on : .off
        stackView.addArrangedSubview(launchCheck)

        addSeparator(to: stackView)

        let info = NSTextField(wrappingLabelWithString: "Left-click the timer to toggle stay awake. Right-click for the full menu.")
        info.textColor = .secondaryLabelColor
        info.font = .systemFont(ofSize: 11)
        stackView.addArrangedSubview(info)

        addSeparator(to: stackView)

        let restoreBtn = NSButton(title: "Restore default settings", target: self, action: #selector(restoreDefaults))
        restoreBtn.bezelStyle = .rounded
        stackView.addArrangedSubview(restoreBtn)
    }

    // MARK: - Helpers

    private func makeCollapsibleStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        return stack
    }

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

    private func selectShakePopup(_ popup: NSPopUpButton) {
        if !Preferences.reminderShakeEnabled {
            popup.selectItem(at: 0) // Off
        } else {
            let mode = Preferences.reminderShakeMode
            switch mode {
            case "0.4": popup.selectItem(at: 1)
            case "1": popup.selectItem(at: 2)
            case "2": popup.selectItem(at: 3)
            case "5": popup.selectItem(at: 4)
            case "until_break": popup.selectItem(at: 5)
            default: popup.selectItem(at: 6) // Custom
            }
        }
    }

    private func isCustomShakeMode() -> Bool {
        guard Preferences.reminderShakeEnabled else { return false }
        return !["0.4", "1", "2", "5", "until_break"].contains(Preferences.reminderShakeMode)
    }

    // MARK: - Restore Defaults

    @objc private func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "Restore default settings?"
        alert.informativeText = "This will reset all settings to their defaults. Session history will not be affected."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Preferences.restoreDefaults()

        // Rebuild UI to reflect defaults
        indicatorButtons.removeAll()
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        setupUI()
    }

    // MARK: - Timer Actions

    @objc private func toggleSeconds(_ sender: NSButton) {
        Preferences.showSeconds = sender.state == .on
    }

    // MARK: - Break Reminder Actions

    @objc private func toggleReminder(_ sender: NSButton) {
        let on = sender.state == .on
        Preferences.reminderEnabled = on
        breakReminderContent.isHidden = !on
    }

    @objc private func bannerChanged(_ sender: NSPopUpButton) {
        let enabling = sender.indexOfSelectedItem == 1
        Preferences.reminderBannerEnabled = enabling

        if enabling {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                            if !granted {
                                DispatchQueue.main.async { self.showNotificationDeniedAlert() }
                            }
                        }
                    case .denied:
                        self.showNotificationDeniedAlert()
                    default:
                        break
                    }
                }
            }
        }
    }

    private func showNotificationDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications disabled"
        alert.informativeText = "Banner notifications need permission. You can enable it in System Settings > Notifications > Time On."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            let bundleId = Bundle.main.bundleIdentifier ?? "com.timeon.app"
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func soundSelectionChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem == 0 {
            Preferences.reminderSoundEnabled = false
            soundOptions.isHidden = true
        } else {
            Preferences.reminderSoundEnabled = true
            Preferences.reminderSoundName = sender.selectedItem?.title ?? "Glass"
            soundOptions.isHidden = false
        }
    }

    @objc private func previewSound() {
        let name = Preferences.reminderSoundEnabled ? Preferences.reminderSoundName : "Glass"
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = Preferences.reminderSoundVolume
        sound.play()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        Preferences.reminderSoundVolume = sender.floatValue
    }

    @objc private func shakeSelectionChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        // 0=Off, 1=0.4s, 2=1s, 3=2s, 4=5s, 5=Until break, 6=Custom
        let modes = ["off", "0.4", "1", "2", "5", "until_break", "custom"]
        guard idx >= 0, idx < modes.count else { return }

        if idx == 0 {
            Preferences.reminderShakeEnabled = false
            shakeOptions.isHidden = true
        } else if idx == 6 {
            Preferences.reminderShakeEnabled = true
            let customVal = shakeCustomField.stringValue
            Preferences.reminderShakeMode = customVal.isEmpty ? "0.4" : customVal
            shakeOptions.isHidden = false
        } else {
            Preferences.reminderShakeEnabled = true
            Preferences.reminderShakeMode = modes[idx]
            shakeOptions.isHidden = true
        }
    }

    @objc private func toggleColorBefore(_ sender: NSButton) {
        Preferences.colorBeforeBreakEnabled = sender.state == .on
    }

    @objc private func toggleColorAfter(_ sender: NSButton) {
        Preferences.colorAfterBreakEnabled = sender.state == .on
    }

    @objc private func colorBeforeChanged(_ sender: NSColorWell) {
        Preferences.colorBeforeBreak = sender.color.hexString
    }

    @objc private func colorAfterChanged(_ sender: NSColorWell) {
        Preferences.colorAfterBreak = sender.color.hexString
    }

    // MARK: - Stay Awake Actions

    @objc private func selectPreset(_ sender: NSButton) {
        deselectAllPresets()
        sender.state = .on
        Preferences.awakeIndicatorIndex = sender.tag
        updatePreview()
    }

    @objc private func useCustomIndicator() {
        let value = customField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        Preferences.customAwakeIndicator = value
        Preferences.awakeIndicatorIndex = -1
        deselectAllPresets()
        updatePreview()
    }

    // MARK: - General Actions

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLoginManager.setEnabled(sender.state == .on)
    }
}

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        switch field.tag {
        case 1:
            Preferences.reminderIntervalMinutes = max(0.1, Double(field.stringValue) ?? 20)
        case 2:
            Preferences.idleThresholdMinutes = max(1, field.integerValue)
        case 3:
            Preferences.defaultAwakeDurationMinutes = max(1, field.integerValue)
        case 5:
            let val = max(0.1, Double(field.stringValue) ?? 0.4)
            Preferences.reminderShakeMode = String(val)
        default:
            break
        }
    }
}
