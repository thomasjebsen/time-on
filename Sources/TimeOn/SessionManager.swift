import Foundation

final class SessionManager {
    private var timer: Timer?
    private var sessionStart: Date?
    private var lastActiveTime: Date = Date()
    private var totalActiveSeconds: TimeInterval = 0
    private(set) var isIdle = false
    private var lastReminderTime: Date?
    private var enabled = true

    /// True while the machine is asleep or the screen is locked. Distinct from
    /// `isIdle` (user inactivity) so the tick loop won't start a phantom session
    /// while suspended.
    private var suspended = false

    /// Start-of-day the current `todayTotalSeconds` belongs to, for midnight rollover.
    private var todayAnchor: Date?

    var idleTimeProvider: () -> TimeInterval = IdleDetector.systemIdleTime

    /// Whether the current session has exceeded the reminder interval.
    private(set) var isOverdue = false

    var onUpdate: ((String, TimeInterval, Bool) -> Void)?  // (formatted, elapsed, isOverdue)
    var onBreakReminder: (() -> Void)?
    var onSessionStateChanged: (() -> Void)?

    /// Fired when a Pomodoro phase ends, passing the phase that just finished.
    var onPomodoroPhaseEnded: ((PomodoroPhase) -> Void)?

    // MARK: - Pomodoro state

    enum PomodoroPhase { case work, shortBreak, longBreak }

    private(set) var pomodoroActive = false
    private(set) var pomodoroPhase: PomodoroPhase = .work
    private var pomodoroPhaseEnd: Date?          // wall-clock end of current phase
    private var completedWorkIntervals = 0
    private(set) var pomodoroRemainingSeconds: Int = 0

    /// Previous session info for display in menu.
    private(set) var previousSessionStart: Date?
    private(set) var previousSessionEnd: Date?
    private(set) var previousSessionDuration: TimeInterval = 0

    /// Time when the last session ended (for "continue" feature).
    private var lastSessionEndTime: Date?
    private var lastSessionAccumulated: TimeInterval = 0

    /// Start time of current session.
    var sessionStartTime: Date? { sessionStart }

    /// Total active time today across all sessions.
    private(set) var todayTotalSeconds: TimeInterval = 0

    /// Current session duration in seconds.
    var currentSessionSeconds: TimeInterval {
        guard sessionStart != nil, !isIdle else { return totalActiveSeconds }
        return totalActiveSeconds + Date().timeIntervalSince(lastActiveTime)
    }

    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TimeOn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func start() {
        loadTodayTotal()
        startNewSession()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        endCurrentSession()
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        enabled.toggle()
        if enabled {
            startNewSession()
        } else {
            endCurrentSession()
        }
    }

    var isEnabled: Bool { enabled }

    /// Whether the user can continue the previous session (ended within 10 minutes).
    var canContinueLastSession: Bool {
        guard let endTime = lastSessionEndTime else { return false }
        return Date().timeIntervalSince(endTime) < 600 // 10 minutes
    }

    func continueLastSession() {
        guard canContinueLastSession else { return }
        // Undo the previous session's end-accounting so the merged session is
        // saved to history and added to the today-total exactly once when it ends.
        rollbackLastSavedSession()
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = lastSessionAccumulated
        isIdle = false
        lastReminderTime = Date()
        lastSessionEndTime = nil
        onSessionStateChanged?()
    }

    /// Reverses the accounting performed by `endCurrentSession` for the most
    /// recently ended session (used by "continue last session" to avoid
    /// double-counting the base duration).
    private func rollbackLastSavedSession() {
        todayTotalSeconds = max(0, todayTotalSeconds - lastSessionAccumulated)
        guard let start = previousSessionStart else { return }
        let startStr = ISO8601DateFormatter().string(from: start)
        var history = loadHistory()
        if let idx = history.lastIndex(where: { $0.date == startStr }) {
            history.remove(at: idx)
            if let data = try? JSONEncoder().encode(history) {
                try? data.write(to: historyFileURL, options: .atomic)
            }
        }
    }

    func handleSleep() {
        // The `suspended` latch also de-dupes: sleep and screen-lock can both
        // fire; only the first ends the session and suspends.
        guard enabled, !suspended else { return }
        // Suspend rather than mark idle: while suspended the tick loop won't
        // restart a session (idle time is low right after a manual lock).
        suspended = true
        endCurrentSession() // no-op if there is no active session
    }

    func handleWake() {
        // Only resume if we were actually suspended. This de-dupes wake+unlock
        // (both fire on a real sleep→wake→unlock) into a single new session, and
        // makes an unpaired wake a no-op that leaves any active session intact
        // rather than discarding it.
        guard enabled, suspended else { return }
        suspended = false
        isIdle = false
        startNewSession()
        onSessionStateChanged?()
    }

    func resetSession() {
        endCurrentSession()
        totalActiveSeconds = 0
        startNewSession()
    }

    func resetBreak() {
        isOverdue = false
        lastReminderTime = Date()
    }

    func startNewSession() {
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = 0
        isIdle = false
        isOverdue = false
        lastReminderTime = Date()
    }

    func tick() {
        // Pomodoro is wall-clock and independent of the activity timer / idle state.
        updatePomodoro()

        guard enabled else {
            onUpdate?(formatTime(0), 0, false)
            return
        }
        guard !suspended else { return }

        // Roll the today-total over when the calendar day changes.
        let currentDay = Calendar.current.startOfDay(for: Date())
        if let anchor = todayAnchor {
            if currentDay != anchor {
                loadTodayTotal()
            }
        } else {
            todayAnchor = currentDay
        }

        let idleSeconds = idleTimeProvider()
        let idleThreshold = TimeInterval(Preferences.idleThresholdMinutes * 60)

        if idleSeconds >= idleThreshold {
            if !isIdle {
                // Transition to idle: end current session, start fresh on return.
                // Exclude the idle grace period from the recorded active time.
                totalActiveSeconds += max(0, Date().timeIntervalSince(lastActiveTime) - idleSeconds)
                isIdle = true
                endCurrentSession()
            }
        } else if isIdle {
            // Returning from idle: start a brand new session
            isIdle = false
            startNewSession()
            onSessionStateChanged?()
        } else if sessionStart == nil {
            // Safety: session was ended but not idle — restart
            startNewSession()
        }

        let elapsed: TimeInterval
        if isIdle {
            elapsed = 0
        } else {
            elapsed = totalActiveSeconds + Date().timeIntervalSince(lastActiveTime)
        }

        // Break reminder check
        if Preferences.reminderEnabled && !isIdle {
            let reminderInterval = TimeInterval(Preferences.reminderIntervalMinutes * 60)
            if let lastReminder = lastReminderTime,
               Date().timeIntervalSince(lastReminder) >= reminderInterval {
                isOverdue = true
                lastReminderTime = Date()
                sendBreakReminder(elapsed: elapsed)
                onBreakReminder?()
            }
        }

        let formatted = formatTime(elapsed)
        onUpdate?(formatted, elapsed, isOverdue)
    }

    private func sendBreakReminder(elapsed: TimeInterval) {
        guard Preferences.reminderBannerEnabled else { return }
        // Sound is handled independently by StatusBarController.
        NotificationManager.shared.send(
            title: "Time for a break",
            body: "You've been active for \(formatTime(elapsed)). Consider taking a short break.",
            identifierPrefix: "breakReminder"
        )
    }

    // MARK: - Pomodoro

    /// Countdown string for the current phase, e.g. "24:15".
    var pomodoroDisplay: String {
        let secs = max(0, pomodoroRemainingSeconds)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    /// Human-readable label for the current phase (menu).
    var pomodoroPhaseLabel: String {
        switch pomodoroPhase {
        case .work: return "Work"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    func startPomodoro() {
        pomodoroActive = true
        pomodoroPhase = .work
        completedWorkIntervals = 0
        let d = durationForPhase(.work)
        pomodoroPhaseEnd = Date().addingTimeInterval(d)
        pomodoroRemainingSeconds = Int(d)
        onSessionStateChanged?()
    }

    func stopPomodoro() {
        pomodoroActive = false
        pomodoroPhaseEnd = nil
        onSessionStateChanged?()
    }

    func skipPomodoroPhase() {
        guard pomodoroActive else { return }
        advancePomodoroPhase()
    }

    private func durationForPhase(_ phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: return TimeInterval(Preferences.pomodoroWorkMinutes * 60)
        case .shortBreak: return TimeInterval(Preferences.pomodoroShortBreakMinutes * 60)
        case .longBreak: return TimeInterval(Preferences.pomodoroLongBreakMinutes * 60)
        }
    }

    private func updatePomodoro() {
        guard pomodoroActive, let end = pomodoroPhaseEnd else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            advancePomodoroPhase()
        } else {
            pomodoroRemainingSeconds = Int(ceil(remaining))
        }
    }

    private func advancePomodoroPhase() {
        let finished = pomodoroPhase
        switch pomodoroPhase {
        case .work:
            completedWorkIntervals += 1
            if completedWorkIntervals >= Preferences.pomodoroIntervalsUntilLongBreak {
                completedWorkIntervals = 0
                pomodoroPhase = .longBreak
            } else {
                pomodoroPhase = .shortBreak
            }
        case .shortBreak, .longBreak:
            pomodoroPhase = .work
        }
        let d = durationForPhase(pomodoroPhase)
        pomodoroPhaseEnd = Date().addingTimeInterval(d)
        pomodoroRemainingSeconds = Int(d)
        sendPomodoroNotification(next: pomodoroPhase)
        onPomodoroPhaseEnded?(finished)
        onSessionStateChanged?()
    }

    private func sendPomodoroNotification(next: PomodoroPhase) {
        guard Preferences.pomodoroBannerEnabled else { return }

        let title: String
        let body: String
        switch next {
        case .work:
            title = "Break over"
            body = "Time to get back to work."
        case .shortBreak:
            title = "Time for a break"
            body = "Nice work — take a short break."
        case .longBreak:
            title = "Time for a long break"
            body = "Set completed — take a long break."
        }
        // Sound is handled independently by StatusBarController.
        NotificationManager.shared.send(title: title, body: body, identifierPrefix: "pomodoro")
    }

    func formatTimeLong(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 && minutes > 0 {
            let h = hours == 1 ? "1 hour" : "\(hours) hours"
            let m = minutes == 1 ? "1 minute" : "\(minutes) minutes"
            return "\(h), \(m)"
        } else if hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        } else if minutes == 0 {
            return totalSeconds <= 0 ? "0 minutes" : "less than a minute"
        } else {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if Preferences.showSeconds {
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        } else {
            if hours > 0 {
                return String(format: "%dh %dm", hours, minutes)
            }
            return String(format: "%dm", minutes)
        }
    }

    // MARK: - History

    private func saveSession() {
        guard let start = sessionStart, totalActiveSeconds > 60 else { return }

        let entry = SessionEntry(
            date: ISO8601DateFormatter().string(from: start),
            durationSeconds: Int(totalActiveSeconds)
        )

        var history = loadHistory()
        history.append(entry)

        // Keep last 60 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let formatter = ISO8601DateFormatter()
        history = history.filter {
            guard let date = formatter.date(from: $0.date) else { return false }
            return date >= cutoff
        }

        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFileURL, options: .atomic)
        }
    }

    private func endCurrentSession() {
        guard let start = sessionStart else { return }
        if !isIdle {
            totalActiveSeconds += Date().timeIntervalSince(lastActiveTime)
        }
        saveSession()
        updateTodayTotal()
        let now = Date()
        previousSessionStart = start
        previousSessionEnd = now
        previousSessionDuration = totalActiveSeconds
        lastSessionEndTime = now
        lastSessionAccumulated = totalActiveSeconds
        sessionStart = nil
        onSessionStateChanged?()
    }

    func loadHistory() -> [SessionEntry] {
        guard let data = try? Data(contentsOf: historyFileURL),
              let history = try? JSONDecoder().decode([SessionEntry].self, from: data) else {
            return []
        }
        return history
    }

    func exportHistory(to url: URL, format: ExportFormat) throws {
        let history = loadHistory()
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(history)
            try data.write(to: url, options: .atomic)
        case .csv:
            var csv = "date,duration_seconds,duration_formatted\n"
            for entry in history {
                csv += "\(entry.date),\(entry.durationSeconds),\(formatTime(TimeInterval(entry.durationSeconds)))\n"
            }
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func loadTodayTotal() {
        let history = loadHistory()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()

        todayAnchor = today
        todayTotalSeconds = history
            .filter {
                guard let date = formatter.date(from: $0.date) else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }
            .reduce(0) { $0 + TimeInterval($1.durationSeconds) }
    }

    private func updateTodayTotal() {
        todayTotalSeconds += totalActiveSeconds
    }
}

struct SessionEntry: Codable {
    let date: String
    let durationSeconds: Int
}

enum ExportFormat {
    case json
    case csv
}

