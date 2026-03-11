import Cocoa

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let sessionManager: SessionManager
    private let caffeineManager = CaffeineManager()
    private var historyWindow: HistoryWindowController?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var onPreferences: (() -> Void)?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupButton()

        sessionManager.onUpdate = { [weak self] formatted, _ in
            DispatchQueue.main.async { self?.updateDisplay(formatted) }
        }

        sessionManager.onBreakReminder = { [weak self] in
            self?.shakeMenuBarIcon()
        }

        sessionManager.onSessionStateChanged = { [weak self] in
            DispatchQueue.main.async { self?.updateDisplay(self?.lastFormatted ?? "0m") }
        }

        caffeineManager.onStateChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.updateDisplay(self?.lastFormatted ?? "0m") }
        }
    }

    private var lastFormatted = "0m"

    private func setupButton() {
        if let button = statusItem.button {
            button.title = "0m"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            caffeineManager.toggle()
        }
    }

    private func showContextMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    // MARK: - Custom Menu Views (bypass isEnabled greying)

    private func makeTextView(text: String, font: NSFont, color: NSColor, height: CGFloat = 22, indent: CGFloat = 14) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: height))
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func addSectionHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = makeTextView(
            text: title,
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .labelColor,
            height: 20
        )
        menu.addItem(item)
    }

    private func addInfoLine(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = makeTextView(
            text: text,
            font: .systemFont(ofSize: 13),
            color: .labelColor,
            height: 22
        )
        menu.addItem(item)
    }

    // MARK: - Menu Construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // — Current Session —
        addSectionHeader("Current session", to: menu)
        if let startTime = sessionManager.sessionStartTime {
            addInfoLine("Started at \(timeFormatter.string(from: startTime))", to: menu)
        } else {
            addInfoLine("No active session", to: menu)
        }

        menu.addItem(NSMenuItem.separator())

        // — Previous Session —
        if let prevStart = sessionManager.previousSessionStart,
           let prevEnd = sessionManager.previousSessionEnd {
            addSectionHeader("Previous session", to: menu)
            addInfoLine(sessionManager.formatTimeLong(sessionManager.previousSessionDuration), to: menu)
            addInfoLine("\(timeFormatter.string(from: prevStart))\u{2009}–\u{2009}\(timeFormatter.string(from: prevEnd))", to: menu)
            menu.addItem(NSMenuItem.separator())
        }

        // — Total Today —
        addSectionHeader("Total today", to: menu)
        let todaySeconds = sessionManager.todayTotalSeconds + sessionManager.currentSessionSeconds
        addInfoLine(sessionManager.formatTimeLong(todaySeconds), to: menu)

        menu.addItem(NSMenuItem.separator())

        // — Caffeine —
        if caffeineManager.isAwake {
            let item = NSMenuItem(title: "Deactivate stay awake", action: #selector(toggleCaffeine), keyEquivalent: "")
            item.target = self
            menu.addItem(item)

            // Show remaining time
            if let remaining = caffeineManager.remainingSeconds {
                let mins = remaining / 60
                let secs = remaining % 60
                let str = mins > 0 ? "\(mins)m \(secs)s remaining" : "\(secs)s remaining"
                let infoItem = NSMenuItem(title: "  \(str)", action: nil, keyEquivalent: "")
                infoItem.isEnabled = false
                menu.addItem(infoItem)
            } else {
                let infoItem = NSMenuItem(title: "  Indefinitely", action: nil, keyEquivalent: "")
                infoItem.isEnabled = false
                menu.addItem(infoItem)
            }
        }

        let activateForItem = NSMenuItem(title: "Activate stay awake for", action: nil, keyEquivalent: "")
        let activateSubmenu = NSMenu()
        for (index, duration) in CaffeineManager.durations.enumerated() {
            let item = NSMenuItem(title: duration.title, action: #selector(activateForDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            activateSubmenu.addItem(item)
        }
        activateSubmenu.addItem(NSMenuItem.separator())
        let customItem = NSMenuItem(title: "Custom...", action: #selector(activateCustomDuration), keyEquivalent: "")
        customItem.target = self
        activateSubmenu.addItem(customItem)
        activateForItem.submenu = activateSubmenu
        menu.addItem(activateForItem)

        menu.addItem(NSMenuItem.separator())

        // — Session controls —
        let resetItem = NSMenuItem(title: "Reset timer", action: #selector(resetTimer), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        if sessionManager.canContinueLastSession {
            let continueItem = NSMenuItem(title: "Continue last session", action: #selector(continueLastSession), keyEquivalent: "")
            continueItem.target = self
            menu.addItem(continueItem)
        }

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "History...", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showPreferences), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        let moreSubmenu = NSMenu()
        let exportJsonItem = NSMenuItem(title: "Export history (JSON)...", action: #selector(exportJSON), keyEquivalent: "")
        exportJsonItem.target = self
        moreSubmenu.addItem(exportJsonItem)
        let exportCsvItem = NSMenuItem(title: "Export history (CSV)...", action: #selector(exportCSV), keyEquivalent: "")
        exportCsvItem.target = self
        moreSubmenu.addItem(exportCsvItem)
        moreItem.submenu = moreSubmenu
        menu.addItem(moreItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Time On", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Display

    private func updateDisplay(_ formatted: String) {
        lastFormatted = formatted
        if let button = statusItem.button {
            if caffeineManager.isAwake {
                let indicator = Preferences.awakeIndicator
                button.title = "\(formatted) \(indicator)"
            } else {
                button.title = formatted
            }
        }
    }

    private func shakeMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -4, 4, -3, 3, -1, 1, 0] as [CGFloat]
        animation.duration = 0.4
        animation.isAdditive = true
        button.layer?.add(animation, forKey: "shake")
    }

    // MARK: - Actions

    @objc private func toggleCaffeine() {
        caffeineManager.toggle()
    }

    @objc private func activateForDuration(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < CaffeineManager.durations.count else { return }
        caffeineManager.activate(duration: CaffeineManager.durations[index].seconds)
    }

    @objc private func activateCustomDuration() {
        let alert = NSAlert()
        alert.messageText = "Custom duration"
        alert.informativeText = "Enter minutes:"
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = "\(Preferences.defaultAwakeDurationMinutes)"
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let minutes = max(1, field.integerValue)
            caffeineManager.activate(duration: TimeInterval(minutes * 60))
        }
    }

    @objc private func resetTimer() {
        sessionManager.resetSession()
    }

    @objc private func continueLastSession() {
        sessionManager.continueLastSession()
    }

    @objc private func showHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindowController(sessionManager: sessionManager)
        }
        historyWindow?.refresh()
        historyWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        onPreferences?()
    }

    @objc private func exportJSON() {
        exportHistory(format: .json, fileType: "json")
    }

    @objc private func exportCSV() {
        exportHistory(format: .csv, fileType: "csv")
    }

    private func exportHistory(format: ExportFormat, fileType: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: fileType)!]
        panel.nameFieldStringValue = "timeon-history.\(fileType)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            try? self?.sessionManager.exportHistory(to: url, format: format)
        }
    }

    @objc private func quit() {
        caffeineManager.deactivate()
        NSApp.terminate(nil)
    }
}
