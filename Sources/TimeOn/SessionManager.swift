import Foundation
import UserNotifications

final class SessionManager {
    private var timer: Timer?
    private var sessionStart: Date?
    private var lastActiveTime: Date = Date()
    private var totalActiveSeconds: TimeInterval = 0
    private(set) var isIdle = false
    private var lastReminderTime: Date?
    private var enabled = true

    var idleTimeProvider: () -> TimeInterval = IdleDetector.systemIdleTime

    var onUpdate: ((String, TimeInterval) -> Void)?
    var onBreakReminder: (() -> Void)?
    var onSessionStateChanged: (() -> Void)?

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
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = lastSessionAccumulated
        isIdle = false
        lastReminderTime = Date()
        lastSessionEndTime = nil
        onSessionStateChanged?()
    }

    func handleSleep() {
        guard enabled, sessionStart != nil else { return }
        if !isIdle {
            totalActiveSeconds += Date().timeIntervalSince(lastActiveTime)
        }
        isIdle = true
        endCurrentSession()
    }

    func handleWake() {
        guard enabled else { return }
        isIdle = false
        startNewSession()
        onSessionStateChanged?()
    }

    func resetSession() {
        endCurrentSession()
        totalActiveSeconds = 0
        startNewSession()
    }

    func startNewSession() {
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = 0
        isIdle = false
        lastReminderTime = Date()
    }

    func tick() {
        guard enabled else {
            onUpdate?(formatTime(0), 0)
            return
        }

        let idleSeconds = idleTimeProvider()
        let idleThreshold = TimeInterval(Preferences.idleThresholdMinutes * 60)

        if idleSeconds >= idleThreshold {
            if !isIdle {
                // Transition to idle: end current session, start fresh on return
                totalActiveSeconds += Date().timeIntervalSince(lastActiveTime)
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

        let formatted = formatTime(elapsed)
        onUpdate?(formatted, elapsed)

        // Break reminder check
        if Preferences.reminderEnabled && !isIdle {
            let reminderInterval = TimeInterval(Preferences.reminderIntervalMinutes * 60)
            if let lastReminder = lastReminderTime,
               Date().timeIntervalSince(lastReminder) >= reminderInterval {
                lastReminderTime = Date()
                sendBreakReminder(elapsed: elapsed)
                onBreakReminder?()
            }
        }
    }

    private func sendBreakReminder(elapsed: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Time for a break"
        content.body = "You've been active for \(formatTime(elapsed)). Consider taking a short break."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "breakReminder-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        } else {
            return minutes <= 1 ? "1 minute" : "\(minutes) minutes"
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
            try? data.write(to: historyFileURL)
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
            try data.write(to: url)
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
