import Cocoa

/// Flipped so short content sits at the top of the scroll view instead of the bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Insights window: today's headline figures, the last four weeks, the daily rhythm, and one
/// day's timeline. All numbers come from `SessionAnalytics`; this class only lays out and formats.
final class InsightsWindowController: NSWindowController, NSWindowDelegate {
    private static let oldestDayOffset = -59
    private static let refreshInterval: TimeInterval = 60

    private let sessionManager: SessionManager
    /// Source of stored sessions. Defaults to the session manager's history file; injectable for previews.
    var historyProvider: () -> [SessionEntry]
    private var calendar = Calendar.current
    private var selectedDayOffset = 0
    private var refreshTimer: Timer?
    private var snapshot: InsightsSnapshot?

    private var stack: NSStackView!

    // Today
    private let todayTile = StatTileView(title: "Total")
    private let longestTile = StatTileView(title: "Longest stretch")
    private let breaksTile = StatTileView(title: "Breaks")

    // Last 4 weeks
    private let dailyChart = BarChartView(height: 120)
    private let dailyReadout = InsightsWindowController.makeReadoutLabel()
    private let weekLabel = InsightsWindowController.makeInfoLabel()

    // When you're active
    private let hourChart = BarChartView(height: 72)
    private let hourReadout = InsightsWindowController.makeReadoutLabel()
    private let typicalLabel = InsightsWindowController.makeInfoLabel()

    // Day
    private var previousDayButton: NSButton!
    private var nextDayButton: NSButton!
    private var todayButton: NSButton!
    private let dayTitleLabel = NSTextField(labelWithString: "Today")
    private let timeline = DayTimelineView()
    private let timelineReadout = InsightsWindowController.makeReadoutLabel()
    private let sessionList = NSStackView()
    private var sessionRows: [(row: NSView, time: NSTextField, duration: NSTextField)] = []

    // Formatters
    private let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter
    }()
    private let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter
    }()
    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
    private let weekdayInitialFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Init

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        self.historyProvider = { sessionManager.loadHistory() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Insights"
        window.minSize = NSSize(width: 420, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("InsightsWindow")

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
        startTimer()
    }

    /// Recomputes and redraws everything. Cheap enough to call on every session change.
    func refresh() {
        calendar = Calendar.current
        let live = sessionManager.sessionStartTime.map {
            LiveSession(start: $0, activeSeconds: sessionManager.currentSessionSeconds)
        }
        let snap = SessionAnalytics.snapshot(
            entries: historyProvider(),
            live: live,
            selectedDayOffset: selectedDayOffset,
            now: Date(),
            calendar: calendar
        )
        snapshot = snap
        apply(snap)
    }

    func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        stopTimer()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = window else { return }
        if window.occlusionState.contains(.visible) {
            startTimer()
            refresh()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: InsightsWindowController.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    @objc private func showPreviousDay() {
        selectDay(offset: selectedDayOffset - 1)
    }

    @objc private func showNextDay() {
        selectDay(offset: selectedDayOffset + 1)
    }

    @objc private func showToday() {
        selectDay(offset: 0)
    }

    private func selectDay(offset: Int) {
        selectedDayOffset = min(0, max(InsightsWindowController.oldestDayOffset, offset))
        refresh()
    }

    // MARK: - Layout

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        document.addSubview(stack)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),

            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        buildTodaySection()
        addSeparator()
        buildTrendSection()
        addSeparator()
        buildRhythmSection()
        addSeparator()
        buildDaySection()
    }

    private func buildTodaySection() {
        addSectionHeader("Today so far")
        let tiles = NSStackView(views: [todayTile, longestTile, breaksTile])
        tiles.orientation = .horizontal
        tiles.distribution = .fillEqually
        tiles.alignment = .top
        tiles.spacing = 12
        addFullWidth(tiles)
    }

    private func buildTrendSection() {
        addSectionHeader("Last 4 weeks")
        addFullWidth(dailyChart)
        addFullWidth(dailyReadout)
        addFullWidth(weekLabel)
        dailyChart.onHover = { [weak self] _ in self?.updateDailyReadout() }
        dailyChart.onSelect = { [weak self] index in
            guard let self = self, let count = self.snapshot?.dailyTotals.count else { return }
            self.selectDay(offset: index - (count - 1))
        }
    }

    private func buildRhythmSection() {
        addSectionHeader("When you're active")
        addFullWidth(hourChart)
        addFullWidth(hourReadout)
        addFullWidth(typicalLabel)
        hourChart.onHover = { [weak self] _ in self?.updateHourReadout() }
    }

    private func buildDaySection() {
        previousDayButton = makeNavButton(symbol: "chevron.left", description: "Previous day", action: #selector(showPreviousDay))
        nextDayButton = makeNavButton(symbol: "chevron.right", description: "Next day", action: #selector(showNextDay))
        todayButton = NSButton(title: "Today", target: self, action: #selector(showToday))
        todayButton.bezelStyle = .texturedRounded
        todayButton.controlSize = .small
        todayButton.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))

        dayTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let header = NSStackView(views: [previousDayButton, nextDayButton, dayTitleLabel, spacer, todayButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.setCustomSpacing(10, after: nextDayButton)
        addFullWidth(header)

        addFullWidth(timeline)
        addFullWidth(timelineReadout)
        timeline.onHover = { [weak self] _ in self?.updateTimelineReadout() }

        sessionList.orientation = .vertical
        sessionList.alignment = .leading
        sessionList.spacing = 0
        addFullWidth(sessionList)
        stack.setCustomSpacing(4, after: timelineReadout)
    }

    // MARK: - Layout helpers

    private func addSectionHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
    }

    private func addFullWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addSeparator() {
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(18, after: last)
        }
        let separator = NSBox()
        separator.boxType = .separator
        addFullWidth(separator)
        stack.setCustomSpacing(16, after: separator)
    }

    private func makeNavButton(symbol: String, description: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private static func makeReadoutLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }

    private static func makeInfoLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }

    private func makeSessionRow() -> (row: NSView, time: NSTextField, duration: NSTextField) {
        let time = NSTextField(labelWithString: "")
        time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        time.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let duration = NSTextField(labelWithString: "")
        duration.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        duration.textColor = .secondaryLabelColor
        duration.alignment = .right
        duration.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [time, duration])
        row.orientation = .horizontal
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true

        sessionList.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: sessionList.widthAnchor).isActive = true
        return (row, time, duration)
    }

    // MARK: - Applying a snapshot

    private func apply(_ snap: InsightsSnapshot) {
        let stats = snap.todayStats
        todayTile.update(value: DurationFormatter.compact(stats.totalSeconds),
                         subtitle: comparisonText(stats.totalVsUsual, today: snap.today))
        longestTile.update(value: DurationFormatter.compact(stats.longestSeconds),
                           subtitle: stats.usualLongestSeconds.map { "usual \(DurationFormatter.compact($0))" } ?? "")
        breaksTile.update(value: "\(stats.breaks)",
                          subtitle: stats.usualBreaks.map { "usual \($0)" } ?? "")

        let lastIndex = snap.dailyTotals.count - 1
        dailyChart.model = BarChartModel(
            bars: snap.dailyTotals.enumerated().map { index, total in
                BarChartModel.Bar(value: Double(total.seconds), hasData: total.hasData, emphasized: index == lastIndex)
            },
            axisLabels: snap.dailyTotals.enumerated().map { index, total in
                BarChartModel.AxisLabel(position: CGFloat(index) + 0.5, text: weekdayInitialFormatter.string(from: total.dayStart))
            },
            referenceLine: snap.windowAverageSeconds.flatMap { average in
                average > 0 ? BarChartModel.ReferenceLine(value: Double(average), label: "avg \(DurationFormatter.compact(average))") : nil
            }
        )
        updateDailyReadout()
        weekLabel.stringValue = weekText(snap.weeks)

        let profile = snap.hourProfile
        hourChart.model = BarChartModel(
            bars: profile.averageMinutes.map { BarChartModel.Bar(value: $0, hasData: profile.daysWithData > 0, emphasized: false) },
            axisLabels: [0, 6, 12, 18, 24].map { BarChartModel.AxisLabel(position: CGFloat($0), text: "\($0)") },
            referenceLine: nil
        )
        updateHourReadout()
        typicalLabel.stringValue = snap.typicalHours.map {
            "Usually start \(DurationFormatter.clock(minuteOfDay: $0.startMinuteOfDay)) · usually stop \(DurationFormatter.clock(minuteOfDay: $0.stopMinuteOfDay))"
        } ?? "Usual hours: not enough data yet"

        let detail = snap.dayDetail
        dayTitleLabel.stringValue = dayTitle(for: detail.dayStart)
        nextDayButton.isEnabled = selectedDayOffset < 0
        previousDayButton.isEnabled = selectedDayOffset > InsightsWindowController.oldestDayOffset
        todayButton.isHidden = selectedDayOffset == 0
        timeline.model = timelineModel(for: detail)
        updateTimelineReadout()
        updateSessionRows(detail)
    }

    private func updateDailyReadout() {
        guard let totals = snapshot?.dailyTotals, !totals.isEmpty else {
            dailyReadout.stringValue = ""
            return
        }
        let index = dailyChart.hoveredIndex ?? totals.count - 1
        guard totals.indices.contains(index) else { return }
        let total = totals[index]
        let name = index == totals.count - 1 ? "Today" : shortDayFormatter.string(from: total.dayStart)
        dailyReadout.stringValue = "\(name) · \(DurationFormatter.compact(total.seconds))"
    }

    private func updateHourReadout() {
        guard let profile = snapshot?.hourProfile else { return }
        if let hour = hourChart.hoveredIndex, profile.averageMinutes.indices.contains(hour) {
            let range = "\(DurationFormatter.clock(minuteOfDay: hour * 60))–\(DurationFormatter.clock(minuteOfDay: (hour + 1) * 60))"
            hourReadout.stringValue = "\(range) · \(DurationFormatter.minutes(profile.averageMinutes[hour])) avg"
        } else {
            hourReadout.stringValue = profile.daysWithData > 0
                ? "Average per hour over the last 4 weeks"
                : "No completed days yet"
        }
    }

    private func updateTimelineReadout() {
        guard let detail = snapshot?.dayDetail else { return }
        if let index = timeline.hoveredIndex {
            if let after = DayTimelineView.gapSegment(index) {
                guard after + 1 < detail.sessions.count else { return }
                let gap = detail.sessions[after + 1].start.timeIntervalSince(detail.sessions[after].end)
                timelineReadout.stringValue = "Break · \(DurationFormatter.minutes(gap / 60))"
            } else if detail.sessions.indices.contains(index) {
                let session = detail.sessions[index]
                timelineReadout.stringValue = "\(timeRange(session)) · \(DurationFormatter.compact(session.seconds))"
            }
        } else {
            timelineReadout.stringValue = summaryText(detail)
        }
    }

    private func updateSessionRows(_ detail: DayDetail) {
        while sessionRows.count < detail.sessions.count {
            sessionRows.append(makeSessionRow())
        }
        for (index, entry) in sessionRows.enumerated() {
            if index < detail.sessions.count {
                let session = detail.sessions[index]
                entry.time.stringValue = timeRange(session)
                entry.duration.stringValue = DurationFormatter.compact(session.seconds)
                entry.row.isHidden = false
            } else {
                entry.row.isHidden = true
            }
        }
    }

    // MARK: - Text

    private func comparisonText(_ comparison: Comparison, today: Date) -> String {
        let weekday = weekdayFormatter.string(from: today)
        switch comparison {
        case .notEnoughData:
            return "not enough data yet"
        case .aboutUsual:
            return "about usual for a \(weekday)"
        case .delta(let seconds, _):
            return "\(DurationFormatter.signedCompact(seconds)) vs usual \(weekday)"
        }
    }

    private func weekText(_ weeks: WeekComparison) -> String {
        var text = "This week \(DurationFormatter.compact(weeks.thisWeekSeconds)) · Last week \(DurationFormatter.compact(weeks.lastWeekSeconds))"
        if let percent = weeks.percentChange {
            let signed = percent < 0 ? "\u{2212}\(-percent)%" : "+\(percent)%"
            text += " (\(signed))"
        }
        return text
    }

    private func dayTitle(for dayStart: Date) -> String {
        switch selectedDayOffset {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return dayTitleFormatter.string(from: dayStart)
        }
    }

    private func summaryText(_ detail: DayDetail) -> String {
        guard !detail.sessions.isEmpty else { return "No sessions" }
        let count = detail.sessions.count
        let sessions = count == 1 ? "1 session" : "\(count) sessions"
        return "\(DurationFormatter.compact(detail.totalSeconds)) · \(sessions) · longest \(DurationFormatter.compact(detail.longestSeconds))"
    }

    private func timeRange(_ session: SessionInterval) -> String {
        let end = session.isLive ? "now" : timeFormatter.string(from: session.end)
        return "\(timeFormatter.string(from: session.start))\u{2009}–\u{2009}\(end)"
    }

    private func timelineModel(for detail: DayDetail) -> DayTimelineModel {
        let segments = detail.sessions.map { session -> DayTimelineModel.Segment in
            let end = calendar.isDate(session.end, inSameDayAs: detail.dayStart)
                ? SessionAnalytics.fractionalMinuteOfDay(session.end, calendar: calendar)
                : 24 * 60
            return DayTimelineModel.Segment(startMinute: SessionAnalytics.fractionalMinuteOfDay(session.start, calendar: calendar),
                                            endMinute: end, isLive: session.isLive)
        }
        return DayTimelineModel(startMinute: detail.timelineStartMinute, endMinute: detail.timelineEndMinute, segments: segments)
    }
}
