#!/usr/bin/env swift

// Self-contained tests for SessionManager logic.
// Run: swift Tests/run_tests.swift

import Foundation
import CoreGraphics

// ─── Minimal copies of production types needed for testing ───

struct Preferences {
    static var idleThresholdMinutes: Int = 5
    static var showSeconds: Bool = false
    static var reminderEnabled: Bool = false
    static var reminderIntervalMinutes: Double = 20
    static var reminderBannerEnabled: Bool = true
    static var reminderSoundEnabled: Bool = false
    static var reminderShakeEnabled: Bool = true
    static var colorBeforeBreakEnabled: Bool = false
    static var colorAfterBreakEnabled: Bool = false

    // Pomodoro
    static var pomodoroWorkMinutes: Int = 25
    static var pomodoroShortBreakMinutes: Int = 5
    static var pomodoroLongBreakMinutes: Int = 15
    static var pomodoroIntervalsUntilLongBreak: Int = 4
    static var pomodoroBannerEnabled: Bool = true

    static func reset() {
        idleThresholdMinutes = 5
        showSeconds = false
        reminderEnabled = false
        reminderIntervalMinutes = 20.0
        reminderBannerEnabled = true
        reminderSoundEnabled = false
        reminderShakeEnabled = true
        colorBeforeBreakEnabled = false
        colorAfterBreakEnabled = false
        pomodoroWorkMinutes = 25
        pomodoroShortBreakMinutes = 5
        pomodoroLongBreakMinutes = 15
        pomodoroIntervalsUntilLongBreak = 4
        pomodoroBannerEnabled = true
    }
}

struct IdleDetector {
    static func systemIdleTime() -> TimeInterval { 0 }
}

// A faithful mirror of the production SessionManager's time-accounting, with an
// injectable clock (`now`) and in-memory stand-ins for the on-disk history and
// today-total so the accounting can be tested deterministically.
final class SessionManager {
    private var sessionStart: Date?
    private var lastActiveTime: Date = Date()
    private var totalActiveSeconds: TimeInterval = 0
    private(set) var isIdle = false
    private(set) var isOverdue = false
    var lastReminderTime: Date?
    private var enabled = true
    private var suspended = false

    /// Test-controllable clock. Defaults to the real wall clock.
    var now: () -> Date = { Date() }

    /// In-memory stand-ins for `history.json` and the running today-total.
    private(set) var savedSessions: [(start: Date, duration: TimeInterval)] = []
    private(set) var todayTotalSeconds: TimeInterval = 0
    private var todayAnchor: Date?

    // Previous session info + "continue" bookkeeping.
    private(set) var previousSessionStart: Date?
    private(set) var previousSessionDuration: TimeInterval = 0
    private var lastSessionEndTime: Date?
    private var lastSessionAccumulated: TimeInterval = 0

    var idleTimeProvider: () -> TimeInterval = IdleDetector.systemIdleTime
    var onUpdate: ((String, TimeInterval, Bool) -> Void)?
    var onBreakReminder: (() -> Void)?
    var onSessionStateChanged: (() -> Void)?

    var sessionStartTime: Date? { sessionStart }

    var currentSessionSeconds: TimeInterval {
        guard sessionStart != nil, !isIdle else { return totalActiveSeconds }
        return totalActiveSeconds + now().timeIntervalSince(lastActiveTime)
    }

    var canContinueLastSession: Bool {
        guard let end = lastSessionEndTime else { return false }
        return now().timeIntervalSince(end) < 600
    }

    func start() {
        loadTodayTotal()
        startNewSession()
    }

    func startNewSession() {
        sessionStart = now()
        lastActiveTime = now()
        totalActiveSeconds = 0
        isIdle = false
        isOverdue = false
        lastReminderTime = now()
    }

    func continueLastSession() {
        guard canContinueLastSession else { return }
        // Undo the previous session's end-accounting so the merged session is
        // saved and counted exactly once when it finally ends.
        rollbackLastSavedSession()
        sessionStart = now()
        lastActiveTime = now()
        totalActiveSeconds = lastSessionAccumulated
        isIdle = false
        lastReminderTime = now()
        lastSessionEndTime = nil
        onSessionStateChanged?()
    }

    private func rollbackLastSavedSession() {
        todayTotalSeconds = max(0, todayTotalSeconds - lastSessionAccumulated)
        guard let start = previousSessionStart else { return }
        if let idx = savedSessions.lastIndex(where: { $0.start == start }) {
            savedSessions.remove(at: idx)
        }
    }

    func resetSession() {
        endCurrentSession()
        totalActiveSeconds = 0
        startNewSession()
    }

    func resetBreak() {
        isOverdue = false
        lastReminderTime = now()
    }

    func handleSleep() {
        // The `suspended` latch also de-dupes sleep + screen-lock.
        guard enabled, !suspended else { return }
        // Suspend rather than mark idle: while suspended the tick loop won't
        // spin up a phantom session (idle time is low right after a manual lock).
        suspended = true
        endCurrentSession() // no-op if there is no active session
    }

    func handleWake() {
        // Only resume if actually suspended: de-dupes wake+unlock and makes an
        // unpaired wake a no-op that leaves any active session intact.
        guard enabled, suspended else { return }
        suspended = false
        isIdle = false
        startNewSession()
        onSessionStateChanged?()
    }

    func tick() {
        guard enabled else {
            onUpdate?("0:00", 0, false)
            return
        }
        guard !suspended else { return }

        // Roll the today-total over at midnight.
        let currentDay = Calendar.current.startOfDay(for: now())
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
                // Exclude the idle grace period from the recorded active time.
                totalActiveSeconds += max(0, now().timeIntervalSince(lastActiveTime) - idleSeconds)
                isIdle = true
                endCurrentSession()
            }
        } else if isIdle {
            isIdle = false
            startNewSession()
            onSessionStateChanged?()
        } else if sessionStart == nil {
            startNewSession()
        }

        let elapsed: TimeInterval
        if isIdle {
            elapsed = 0
        } else {
            elapsed = totalActiveSeconds + now().timeIntervalSince(lastActiveTime)
        }

        // Break reminder check
        if Preferences.reminderEnabled && !isIdle {
            let reminderInterval = TimeInterval(Preferences.reminderIntervalMinutes * 60)
            if let lastReminder = lastReminderTime,
               now().timeIntervalSince(lastReminder) >= reminderInterval {
                isOverdue = true
                lastReminderTime = now()
                onBreakReminder?()
            }
        }

        onUpdate?(formatTime(elapsed), elapsed, isOverdue)
    }

    func endCurrentSession() {
        guard sessionStart != nil else { return }
        if !isIdle {
            totalActiveSeconds += now().timeIntervalSince(lastActiveTime)
        }
        saveSession()
        updateTodayTotal()
        previousSessionStart = sessionStart
        previousSessionDuration = totalActiveSeconds
        lastSessionEndTime = now()
        lastSessionAccumulated = totalActiveSeconds
        sessionStart = nil
        onSessionStateChanged?()
    }

    private func saveSession() {
        guard let start = sessionStart, totalActiveSeconds > 60 else { return }
        savedSessions.append((start, totalActiveSeconds))
    }

    private func updateTodayTotal() {
        todayTotalSeconds += totalActiveSeconds
    }

    private func loadTodayTotal() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        todayAnchor = today
        todayTotalSeconds = savedSessions
            .filter { cal.isDate($0.start, inSameDayAs: today) }
            .reduce(0) { $0 + $1.duration }
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Pomodoro

    enum PomodoroPhase { case work, shortBreak, longBreak }

    private(set) var pomodoroActive = false
    private(set) var pomodoroPhase: PomodoroPhase = .work
    private var pomodoroPhaseEnd: Date?
    private var completedWorkIntervals = 0
    private(set) var pomodoroRemainingSeconds: Int = 0

    var onPomodoroPhaseEnded: ((PomodoroPhase) -> Void)?

    private func durationForPhase(_ phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: return TimeInterval(Preferences.pomodoroWorkMinutes * 60)
        case .shortBreak: return TimeInterval(Preferences.pomodoroShortBreakMinutes * 60)
        case .longBreak: return TimeInterval(Preferences.pomodoroLongBreakMinutes * 60)
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
        advancePomodoroPhase()
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
        onPomodoroPhaseEnded?(finished)
        onSessionStateChanged?()
    }
}

// ─── Test harness ───

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func test(_ name: String, _ body: () -> Void) {
    Preferences.reset()
    print("• \(name)")
    body()
}

// ─── Idle Detection Tests ───

test("Timer counts up during active use") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    for _ in 0..<5 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed, _ in lastElapsed = elapsed }
    mgr.tick()

    assert(lastElapsed > 0, "Elapsed should be > 0 during active use, got \(lastElapsed)")
    assert(!mgr.isIdle, "Should not be idle when there is input activity")
}

test("Timer keeps counting when idle time is below threshold") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 10.0 }
    mgr.startNewSession()

    for _ in 0..<5 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed, _ in lastElapsed = elapsed }
    mgr.tick()

    assert(lastElapsed > 0, "Timer should keep counting when idle < threshold, got \(lastElapsed)")
    assert(!mgr.isIdle, "Should not be idle")
}

test("Session ends when idle threshold exceeded") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 301.0 }
    mgr.startNewSession()

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed, _ in lastElapsed = elapsed }
    mgr.tick()

    assert(lastElapsed == 0, "Timer should show 0 when idle threshold exceeded, got \(lastElapsed)")
    assert(mgr.isIdle, "Should be marked as idle")
}

test("New session starts on return from idle") {
    var fakeIdleTime: TimeInterval = 301.0
    let mgr = SessionManager()
    mgr.idleTimeProvider = { fakeIdleTime }
    mgr.startNewSession()

    mgr.tick()
    assert(mgr.isIdle, "Should be idle after exceeding threshold")

    fakeIdleTime = 1.0
    mgr.tick()

    assert(!mgr.isIdle, "Should no longer be idle after activity")
    assert(mgr.sessionStartTime != nil, "New session should have started")
}

test("No spurious resets during continuous activity") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { Double.random(in: 0.0...1.5) }
    mgr.startNewSession()

    var sessionStateChanges = 0
    mgr.onSessionStateChanged = { sessionStateChanges += 1 }

    var elapsedValues: [TimeInterval] = []
    mgr.onUpdate = { _, elapsed, _ in elapsedValues.append(elapsed) }

    for _ in 0..<20 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var monotonic = true
    for i in 1..<elapsedValues.count {
        if elapsedValues[i] < elapsedValues[i - 1] {
            monotonic = false
            break
        }
    }

    assert(monotonic, "Elapsed time should never decrease during active use")
    assert(sessionStateChanges == 0, "No session resets during continuous activity, got \(sessionStateChanges)")
}

test("Idle then return produces exactly one reset cycle") {
    var fakeIdleTime: TimeInterval = 0.5
    let mgr = SessionManager()
    mgr.idleTimeProvider = { fakeIdleTime }
    mgr.startNewSession()

    for _ in 0..<5 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var sessionStateChanges = 0
    mgr.onSessionStateChanged = { sessionStateChanges += 1 }

    fakeIdleTime = 301.0
    mgr.tick()

    fakeIdleTime = 0.5
    mgr.tick()

    assert(sessionStateChanges == 2, "Expected 2 state changes (idle + return), got \(sessionStateChanges)")
    assert(!mgr.isIdle, "Should not be idle after returning")
}

// ─── Break Reminder Tests ───

test("Break reminder fires after configured interval") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)

    var reminderFired = false
    mgr.onBreakReminder = { reminderFired = true }
    mgr.tick()

    assert(reminderFired, "Break reminder should fire after interval elapsed")
}

test("Break reminder does NOT fire before interval") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    var reminderFired = false
    mgr.onBreakReminder = { reminderFired = true }
    mgr.tick()

    assert(!reminderFired, "Break reminder should NOT fire before interval")
}

test("Break reminder resets and fires again after another interval") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    var reminderCount = 0
    mgr.onBreakReminder = { reminderCount += 1 }

    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()
    assert(reminderCount == 1, "First reminder should fire, got \(reminderCount)")

    mgr.tick()
    assert(reminderCount == 1, "Should not fire again immediately, got \(reminderCount)")

    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()
    assert(reminderCount == 2, "Second reminder should fire, got \(reminderCount)")
}

test("Break reminder does NOT fire when disabled") {
    Preferences.reminderEnabled = false

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)

    var reminderFired = false
    mgr.onBreakReminder = { reminderFired = true }
    mgr.tick()

    assert(!reminderFired, "Break reminder should NOT fire when disabled")
}

test("Break reminder does NOT fire during idle") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 301.0 }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)

    var reminderFired = false
    mgr.onBreakReminder = { reminderFired = true }
    mgr.tick()

    assert(!reminderFired, "Break reminder should NOT fire when user is idle")
}

test("Break reminder timer resets on new session (return from idle)") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    var fakeIdleTime: TimeInterval = 0.5
    let mgr = SessionManager()
    mgr.idleTimeProvider = { fakeIdleTime }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-19 * 60)

    fakeIdleTime = 301.0
    mgr.tick()

    fakeIdleTime = 0.5
    mgr.tick()

    var reminderFired = false
    mgr.onBreakReminder = { reminderFired = true }
    mgr.tick()

    assert(!reminderFired, "Break reminder timer should reset after idle return, not carry over")
}

// ─── Overdue State Tests ───

test("isOverdue becomes true when reminder fires") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    assert(!mgr.isOverdue, "Should not be overdue initially")

    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()

    assert(mgr.isOverdue, "Should be overdue after reminder fires")
}

test("isOverdue stays true after reminder fires") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()

    assert(mgr.isOverdue, "Should be overdue")

    // Subsequent ticks should stay overdue
    mgr.tick()
    assert(mgr.isOverdue, "Should still be overdue on next tick")
}

test("isOverdue resets on new session") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    var fakeIdleTime: TimeInterval = 0.5
    let mgr = SessionManager()
    mgr.idleTimeProvider = { fakeIdleTime }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()

    assert(mgr.isOverdue, "Should be overdue")

    // Go idle and return
    fakeIdleTime = 301.0
    mgr.tick()
    fakeIdleTime = 0.5
    mgr.tick()

    assert(!mgr.isOverdue, "Should not be overdue after new session")
}

test("isOverdue passed through onUpdate callback") {
    Preferences.reminderEnabled = true
    Preferences.reminderIntervalMinutes = 20

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    var lastOverdue = false
    mgr.onUpdate = { _, _, overdue in lastOverdue = overdue }

    mgr.tick()
    assert(!lastOverdue, "Should not be overdue initially")

    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)
    mgr.tick()
    assert(lastOverdue, "Should report overdue via onUpdate")
}

test("isOverdue is false when reminders disabled") {
    Preferences.reminderEnabled = false

    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()
    mgr.lastReminderTime = Date().addingTimeInterval(-21 * 60)

    var lastOverdue = false
    mgr.onUpdate = { _, _, overdue in lastOverdue = overdue }
    mgr.tick()

    assert(!lastOverdue, "Should not be overdue when reminders disabled")
}

// ─── Pomodoro Tests ───

test("startPomodoro activates and begins with a work phase") {
    let mgr = SessionManager()
    assert(!mgr.pomodoroActive, "Should be inactive before start")

    mgr.startPomodoro()

    assert(mgr.pomodoroActive, "Should be active after start")
    assert(mgr.pomodoroPhase == .work, "Should start in work phase")
    assert(mgr.pomodoroRemainingSeconds == 25 * 60, "Work phase should be 25 minutes, got \(mgr.pomodoroRemainingSeconds)")
}

test("stopPomodoro deactivates") {
    let mgr = SessionManager()
    mgr.startPomodoro()
    mgr.stopPomodoro()

    assert(!mgr.pomodoroActive, "Should be inactive after stop")
}

test("Phase sequence: work -> short break -> work, long break after 4 work intervals") {
    Preferences.pomodoroIntervalsUntilLongBreak = 4

    let mgr = SessionManager()
    mgr.startPomodoro()

    // Expected sequence of the phase we land in after each skip, starting from work.
    let expected: [SessionManager.PomodoroPhase] = [
        .shortBreak, .work,   // 1st work done
        .shortBreak, .work,   // 2nd work done
        .shortBreak, .work,   // 3rd work done
        .longBreak,  .work,   // 4th work done -> long break, then back to work
    ]

    for (i, phase) in expected.enumerated() {
        mgr.skipPomodoroPhase()
        assert(mgr.pomodoroPhase == phase, "Step \(i): expected \(phase), got \(mgr.pomodoroPhase)")
    }
}

test("pomodoroIntervalsUntilLongBreak is respected when changed") {
    Preferences.pomodoroIntervalsUntilLongBreak = 2

    let mgr = SessionManager()
    mgr.startPomodoro()

    mgr.skipPomodoroPhase() // work 1 done -> short break
    assert(mgr.pomodoroPhase == .shortBreak, "After 1st work: short break, got \(mgr.pomodoroPhase)")
    mgr.skipPomodoroPhase() // short break -> work 2
    assert(mgr.pomodoroPhase == .work, "Back to work, got \(mgr.pomodoroPhase)")
    mgr.skipPomodoroPhase() // work 2 done -> long break (2 intervals reached)
    assert(mgr.pomodoroPhase == .longBreak, "After 2nd work: long break, got \(mgr.pomodoroPhase)")
}

test("onPomodoroPhaseEnded reports the phase that just finished") {
    let mgr = SessionManager()
    mgr.startPomodoro()

    var finishedPhases: [SessionManager.PomodoroPhase] = []
    mgr.onPomodoroPhaseEnded = { finishedPhases.append($0) }

    mgr.skipPomodoroPhase() // finishes work
    mgr.skipPomodoroPhase() // finishes short break

    assert(finishedPhases == [.work, .shortBreak], "Expected [work, shortBreak], got \(finishedPhases)")
}

// ─── Time Accounting Tests (regressions the old mirror harness could not express) ───

test("Idle-ended session excludes the idle grace period from recorded time") {
    Preferences.idleThresholdMinutes = 5 // 300s threshold
    let mgr = SessionManager()
    var clock = Date(timeIntervalSince1970: 1_000_000)
    mgr.now = { clock }
    mgr.idleTimeProvider = { 0 }
    mgr.startNewSession()

    // 15 minutes elapse; the user's last real input was 5 minutes ago (idle threshold hit).
    clock = clock.addingTimeInterval(15 * 60)
    mgr.idleTimeProvider = { 300 }
    mgr.tick()

    assert(mgr.previousSessionDuration == 600,
           "Recorded active time should be 10min (15min − 5min idle grace), got \(Int(mgr.previousSessionDuration))s")
}

test("Continuing a session does not double-count today's total or history") {
    Preferences.idleThresholdMinutes = 5
    let mgr = SessionManager()
    var clock = Date(timeIntervalSince1970: 2_000_000)
    mgr.now = { clock }
    mgr.idleTimeProvider = { 0 }

    mgr.startNewSession()
    clock = clock.addingTimeInterval(600) // 10 min
    mgr.endCurrentSession()               // session A saved + counted

    clock = clock.addingTimeInterval(120) // user returns within 10 min
    mgr.continueLastSession()
    clock = clock.addingTimeInterval(300) // 5 more min
    mgr.endCurrentSession()

    assert(mgr.todayTotalSeconds == 900,
           "Today total should count the merged 15min once, got \(Int(mgr.todayTotalSeconds))s")
    assert(mgr.savedSessions.map { Int($0.duration) } == [900],
           "History should hold one merged 15min session, got \(mgr.savedSessions.map { Int($0.duration) })")
}

test("Today total resets when the day rolls over") {
    Preferences.idleThresholdMinutes = 5
    let cal = Calendar.current
    let mgr = SessionManager()
    var clock = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12, minute: 0))!
    mgr.now = { clock }
    mgr.idleTimeProvider = { 0 }

    mgr.start()
    clock = clock.addingTimeInterval(600)
    mgr.endCurrentSession()               // 10 min saved for June 1
    mgr.startNewSession()
    mgr.tick()
    assert(mgr.todayTotalSeconds == 600, "Same day keeps the total, got \(Int(mgr.todayTotalSeconds))s")

    // Cross midnight into June 2.
    clock = cal.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 0, minute: 5))!
    mgr.tick()
    assert(mgr.todayTotalSeconds == 0,
           "Today total should reset after midnight, got \(Int(mgr.todayTotalSeconds))s")
}

test("formatTimeLong renders sub-minute and zero durations honestly") {
    let mgr = SessionManager()
    assert(mgr.formatTimeLong(0) == "0 minutes", "0s → '0 minutes', got '\(mgr.formatTimeLong(0))'")
    assert(mgr.formatTimeLong(30) == "less than a minute", "30s → 'less than a minute', got '\(mgr.formatTimeLong(30))'")
    assert(mgr.formatTimeLong(60) == "1 minute", "60s → '1 minute', got '\(mgr.formatTimeLong(60))'")
    assert(mgr.formatTimeLong(120) == "2 minutes", "120s → '2 minutes', got '\(mgr.formatTimeLong(120))'")
}

test("Locked/suspended screen does not start a phantom session until wake") {
    Preferences.idleThresholdMinutes = 5
    let mgr = SessionManager()
    let clock = Date(timeIntervalSince1970: 3_000_000)
    mgr.now = { clock }
    mgr.idleTimeProvider = { 1.0 } // low idle — e.g. a manual lock
    mgr.startNewSession()

    mgr.handleSleep()               // screen locked / system suspended
    mgr.tick()                      // a tick fires while suspended
    assert(mgr.sessionStartTime == nil,
           "No session should run while suspended/locked")

    mgr.handleWake()
    assert(mgr.sessionStartTime != nil,
           "A fresh session should start on wake/unlock")
}

test("Unpaired wake leaves the active session intact instead of discarding it") {
    Preferences.idleThresholdMinutes = 5
    let mgr = SessionManager()
    var clock = Date(timeIntervalSince1970: 4_000_000)
    mgr.now = { clock }
    mgr.idleTimeProvider = { 0 }
    mgr.startNewSession()

    clock = clock.addingTimeInterval(600) // 10 min active
    mgr.handleWake()                       // wake with no prior sleep — must not discard

    mgr.endCurrentSession()                // a normal end still records the full 10 min
    assert(mgr.savedSessions.map { Int($0.duration) } == [600],
           "Unpaired wake must not discard active time, got \(mgr.savedSessions.map { Int($0.duration) })")
}

test("Duplicate sleep/wake notifications don't spawn extra sessions") {
    Preferences.idleThresholdMinutes = 5
    let mgr = SessionManager()
    var clock = Date(timeIntervalSince1970: 5_000_000)
    mgr.now = { clock }
    mgr.idleTimeProvider = { 0 }
    mgr.start()

    clock = clock.addingTimeInterval(600)
    mgr.handleSleep()                    // system sleep — ends + suspends
    assert(mgr.savedSessions.map { Int($0.duration) } == [600], "sleep ends the session once")

    clock = clock.addingTimeInterval(30)
    mgr.handleSleep()                    // duplicate (screen lock after sleep) — ignored
    assert(mgr.savedSessions.map { Int($0.duration) } == [600], "duplicate sleep must not end again")

    mgr.handleWake()                     // wake — resume one new session
    let resumed = mgr.sessionStartTime
    clock = clock.addingTimeInterval(120)
    mgr.handleWake()                     // duplicate (unlock after wake) — ignored
    assert(mgr.sessionStartTime == resumed, "duplicate wake must not restart the session")
}

// Mirror of BadgeGeometry in Sources/TimeOn/BadgePanelController.swift — keep in sync.
enum BadgeGeometry {
    static let gapBelowMenuBar: CGFloat = 6
    static let screenInset: CGFloat = 8

    static func cardFrame(size: CGSize, anchor: CGRect?, visibleFrame vf: CGRect) -> CGRect {
        var origin: CGPoint
        if let a = anchor {
            origin = CGPoint(x: a.midX - size.width / 2, y: a.minY - gapBelowMenuBar - size.height)
        } else {
            origin = CGPoint(x: vf.maxX - screenInset - size.width, y: vf.maxY - gapBelowMenuBar - size.height)
        }
        origin.x = min(max(origin.x, vf.minX + screenInset), vf.maxX - screenInset - size.width)
        origin.y = min(max(origin.y, vf.minY + screenInset), vf.maxY - gapBelowMenuBar - size.height)
        return CGRect(origin: origin, size: size)
    }
}

// ─── Badge Geometry Tests ───
// BadgeGeometry.cardFrame is the pure positioning function used by BadgePanelController.

test("Badge is centred under the status item, hanging 6pt below the menu bar") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)          // visibleFrame (menu bar excluded)
    let anchor = CGRect(x: 1200, y: 875, width: 60, height: 22)          // status button, bottom edge = vf.maxY
    let size = CGSize(width: 220, height: 110)
    let f = BadgeGeometry.cardFrame(size: size, anchor: anchor, visibleFrame: screen)
    assert(f.size == size, "size is preserved")
    assert(f.midX == anchor.midX, "horizontally centred under the anchor (got \(f.midX))")
    assert(f.maxY == 875 - 6, "top edge sits 6pt below the menu bar (got \(f.maxY))")
}

test("Badge is clamped inside the screen near the right edge") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let anchor = CGRect(x: 1400, y: 875, width: 40, height: 22)          // last status item, at the very edge
    let size = CGSize(width: 220, height: 110)
    let f = BadgeGeometry.cardFrame(size: size, anchor: anchor, visibleFrame: screen)
    assert(f.maxX == 1440 - 8, "right edge respects the 8pt inset (got \(f.maxX))")
    assert(f.minX >= 0, "never off the left edge")
}

test("Badge stays at the top of the screen when the menu bar is hidden (fullscreen app)") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)          // no menu bar: visibleFrame is the full screen
    let anchor = CGRect(x: 1200, y: 910, width: 60, height: 22)          // status bar window slid above the screen
    let size = CGSize(width: 220, height: 110)
    let f = BadgeGeometry.cardFrame(size: size, anchor: anchor, visibleFrame: screen)
    assert(f.maxY == 900 - 6, "clamped to hang from the top edge (got \(f.maxY))")
    assert(f.midX == anchor.midX, "still centred under where the item is")
}

test("Badge falls back to the top-right corner without an anchor") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 220, height: 110)
    let f = BadgeGeometry.cardFrame(size: size, anchor: nil, visibleFrame: screen)
    assert(f.maxX == 1440 - 8, "right inset (got \(f.maxX))")
    assert(f.maxY == 875 - 6, "top gap (got \(f.maxY))")
}

test("Badge frame is offset correctly on a secondary display with a non-zero origin") {
    let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1055)   // display to the left of the main one
    let anchor = CGRect(x: -300, y: 1255, width: 60, height: 22)
    let size = CGSize(width: 220, height: 110)
    let f = BadgeGeometry.cardFrame(size: size, anchor: anchor, visibleFrame: screen)
    assert(f.midX == anchor.midX, "centred under anchor on the secondary display")
    assert(f.maxY == 1255 - 6, "hangs below that display's menu bar (got \(f.maxY))")
    assert(screen.contains(f), "entirely inside the secondary display")
}

// ─── Results ───

print("")
if failed == 0 {
    print("All \(passed) assertions passed ✓")
} else {
    print("\(failed) assertion(s) FAILED, \(passed) passed")
    exit(1)
}
