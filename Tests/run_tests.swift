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
    }
}

struct IdleDetector {
    static func systemIdleTime() -> TimeInterval { 0 }
}

final class SessionManager {
    private var sessionStart: Date?
    private var lastActiveTime: Date = Date()
    private var totalActiveSeconds: TimeInterval = 0
    private(set) var isIdle = false
    private(set) var isOverdue = false
    var lastReminderTime: Date?
    private var enabled = true

    var idleTimeProvider: () -> TimeInterval = IdleDetector.systemIdleTime
    var onUpdate: ((String, TimeInterval, Bool) -> Void)?
    var onBreakReminder: (() -> Void)?
    var onSessionStateChanged: (() -> Void)?

    var sessionStartTime: Date? { sessionStart }

    func startNewSession() {
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = 0
        isIdle = false
        isOverdue = false
        lastReminderTime = Date()
    }

    func tick() {
        guard enabled else {
            onUpdate?("0m", 0, false)
            return
        }

        let idleSeconds = idleTimeProvider()
        let idleThreshold = TimeInterval(Preferences.idleThresholdMinutes * 60)

        if idleSeconds >= idleThreshold {
            if !isIdle {
                totalActiveSeconds += Date().timeIntervalSince(lastActiveTime)
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
            elapsed = totalActiveSeconds + Date().timeIntervalSince(lastActiveTime)
        }

        // Break reminder check
        if Preferences.reminderEnabled && !isIdle {
            let reminderInterval = TimeInterval(Preferences.reminderIntervalMinutes * 60)
            if let lastReminder = lastReminderTime,
               Date().timeIntervalSince(lastReminder) >= reminderInterval {
                isOverdue = true
                lastReminderTime = Date()
                onBreakReminder?()
            }
        }

        onUpdate?(formatTime(elapsed), elapsed, isOverdue)
    }

    private func endCurrentSession() {
        guard sessionStart != nil else { return }
        if !isIdle {
            totalActiveSeconds += Date().timeIntervalSince(lastActiveTime)
        }
        sessionStart = nil
        onSessionStateChanged?()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
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

// ─── Results ───

print("")
if failed == 0 {
    print("All \(passed) assertions passed ✓")
} else {
    print("\(failed) assertion(s) FAILED, \(passed) passed")
    exit(1)
}
