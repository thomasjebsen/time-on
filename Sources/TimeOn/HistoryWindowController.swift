import Cocoa

final class HistoryWindowController: NSWindowController {
    private let sessionManager: SessionManager
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 300)

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        populateContent()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(stackView)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -20),

            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        populateContent()
    }

    private func populateContent() {
        let history = sessionManager.loadHistory()
        let stats = computeStats(history)

        // Stats section
        addStatRow("Days:", stats.totalDays, to: stackView)
        addStatRow("Total today:", sessionManager.formatTimeLong(stats.totalToday), to: stackView)
        addStatRow("Total yesterday:", sessionManager.formatTimeLong(stats.totalYesterday), to: stackView)
        addStatRow("7-day average:", sessionManager.formatTimeLong(stats.sevenDayAverage), to: stackView)
        addStatRow("Weekday average:", sessionManager.formatTimeLong(stats.weekdayAverage), to: stackView)
        addStatRow("All-time average:", sessionManager.formatTimeLong(stats.allTimeAverage), to: stackView)

        addSpacer(20, to: stackView)

        // Group sessions by day
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        // Parse and group
        var sessionsByDay: [(day: Date, sessions: [(start: Date, duration: Int)])] = []
        var currentDay: Date?
        var currentDaySessions: [(start: Date, duration: Int)] = []

        let sorted = history.compactMap { entry -> (date: Date, duration: Int)? in
            guard let d = formatter.date(from: entry.date) else { return nil }
            return (d, entry.durationSeconds)
        }.sorted { $0.date > $1.date }

        for session in sorted {
            let day = calendar.startOfDay(for: session.date)
            if day != currentDay {
                if let prevDay = currentDay, !currentDaySessions.isEmpty {
                    sessionsByDay.append((prevDay, currentDaySessions))
                }
                currentDay = day
                currentDaySessions = []
            }
            currentDaySessions.append((session.date, session.duration))
        }
        if let prevDay = currentDay, !currentDaySessions.isEmpty {
            sessionsByDay.append((prevDay, currentDaySessions))
        }

        // Render days
        for dayGroup in sessionsByDay {
            let dayTotal = dayGroup.sessions.reduce(0) { $0 + $1.duration }

            addSeparator(to: stackView)

            // Day header
            let headerRow = NSStackView()
            headerRow.orientation = .horizontal
            headerRow.distribution = .fill

            let isToday = calendar.isDateInToday(dayGroup.day)
            let dayLabel = NSTextField(labelWithString: isToday ? "Today" : dayFormatter.string(from: dayGroup.day))
            dayLabel.font = .systemFont(ofSize: 12, weight: .medium)

            let totalLabel = NSTextField(labelWithString: sessionManager.formatTimeLong(TimeInterval(dayTotal)))
            totalLabel.font = .systemFont(ofSize: 12, weight: .regular)
            totalLabel.textColor = .secondaryLabelColor
            totalLabel.alignment = .right

            headerRow.addArrangedSubview(dayLabel)
            headerRow.addArrangedSubview(totalLabel)
            headerRow.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(headerRow)
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            addSpacer(6, to: stackView)

            // Sessions for this day
            for session in dayGroup.sessions {
                let endDate = session.start.addingTimeInterval(TimeInterval(session.duration))
                let card = makeSessionCard(
                    duration: sessionManager.formatTimeLong(TimeInterval(session.duration)),
                    timeRange: "\(timeFormatter.string(from: session.start))\u{2009}–\u{2009}\(timeFormatter.string(from: endDate))"
                )
                stackView.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            }

            addSpacer(8, to: stackView)
        }

        if history.isEmpty {
            let empty = NSTextField(labelWithString: "No sessions recorded yet.")
            empty.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(empty)
        }
    }

    private func makeSessionCard(duration: String, timeRange: String) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false

        let durationLabel = NSTextField(labelWithString: duration)
        durationLabel.font = .systemFont(ofSize: 13, weight: .medium)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        let timeLabel = NSTextField(labelWithString: timeRange)
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(durationLabel)
        card.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 52),
            durationLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            durationLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            timeLabel.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        ])

        return card
    }

    private func addStatRow(_ label: String, _ value: String, to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill

        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 12)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let valueField = NSTextField(labelWithString: value)
        valueField.font = .systemFont(ofSize: 12, weight: .semibold)

        row.addArrangedSubview(labelField)
        row.addArrangedSubview(valueField)
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addStatRow(_ label: String, _ value: Int, to stack: NSStackView) {
        addStatRow(label, "\(value)", to: stack)
    }

    private func addSeparator(to stack: NSStackView) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addSpacer(_ height: CGFloat, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.addArrangedSubview(spacer)
    }

    // MARK: - Stats

    private struct HistoryStats {
        var totalDays: Int
        var totalToday: TimeInterval
        var totalYesterday: TimeInterval
        var sevenDayAverage: TimeInterval
        var weekdayAverage: TimeInterval
        var allTimeAverage: TimeInterval
    }

    private func computeStats(_ history: [SessionEntry]) -> HistoryStats {
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        var dailyTotals: [Date: TimeInterval] = [:]
        var totalToday: TimeInterval = 0
        var totalYesterday: TimeInterval = 0

        for entry in history {
            guard let date = formatter.date(from: entry.date) else { continue }
            let day = calendar.startOfDay(for: date)
            let duration = TimeInterval(entry.durationSeconds)
            dailyTotals[day, default: 0] += duration

            if calendar.isDate(date, inSameDayAs: today) {
                totalToday += duration
            }
            if calendar.isDate(date, inSameDayAs: yesterday) {
                totalYesterday += duration
            }
        }

        let totalDays = dailyTotals.count

        // 7-day average
        let last7 = dailyTotals.filter { $0.key >= sevenDaysAgo }
        let sevenDayAvg = last7.isEmpty ? 0 : last7.values.reduce(0, +) / Double(max(1, last7.count))

        // Weekday average (Mon-Fri)
        let weekdayTotals = dailyTotals.filter {
            let weekday = calendar.component(.weekday, from: $0.key)
            return weekday >= 2 && weekday <= 6
        }
        let weekdayAvg = weekdayTotals.isEmpty ? 0 : weekdayTotals.values.reduce(0, +) / Double(weekdayTotals.count)

        // All-time average
        let allTimeAvg = dailyTotals.isEmpty ? 0 : dailyTotals.values.reduce(0, +) / Double(dailyTotals.count)

        return HistoryStats(
            totalDays: totalDays,
            totalToday: totalToday,
            totalYesterday: totalYesterday,
            sevenDayAverage: sevenDayAvg,
            weekdayAverage: weekdayAvg,
            allTimeAverage: allTimeAvg
        )
    }
}
