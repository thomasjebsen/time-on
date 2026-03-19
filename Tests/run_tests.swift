#!/usr/bin/env swift

// Self-contained test for SessionManager idle detection logic.
// Run: swift Tests/run_tests.swift

import Foundation
import CoreGraphics

// ─── Minimal copies of production types needed for testing ───

struct Preferences {
    private static let defaults = UserDefaults.standard

    static var idleThresholdMinutes: Int {
        let val = defaults.integer(forKey: "idleThresholdMinutes")
        return val > 0 ? val : 5
    }

    static var showSeconds: Bool {
        defaults.object(forKey: "showSeconds") as? Bool ?? false
    }

    static var reminderEnabled: Bool {
        defaults.object(forKey: "reminderEnabled") as? Bool ?? false // disabled for tests
    }

    static var reminderIntervalMinutes: Int { 20 }
}

struct IdleDetector {
    static func systemIdleTime() -> TimeInterval { 0 }
}

final class SessionManager {
    private var sessionStart: Date?
    private var lastActiveTime: Date = Date()
    private var totalActiveSeconds: TimeInterval = 0
    private(set) var isIdle = false
    private var lastReminderTime: Date?
    private var enabled = true

    var idleTimeProvider: () -> TimeInterval = IdleDetector.systemIdleTime
    var onUpdate: ((String, TimeInterval) -> Void)?
    var onSessionStateChanged: (() -> Void)?

    var sessionStartTime: Date? { sessionStart }

    func startNewSession() {
        sessionStart = Date()
        lastActiveTime = Date()
        totalActiveSeconds = 0
        isIdle = false
        lastReminderTime = Date()
    }

    func tick() {
        guard enabled else {
            onUpdate?("0m", 0)
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

        onUpdate?(formatTime(elapsed), elapsed)
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
    print("• \(name)")
    body()
}

// ─── Tests ───

test("Timer counts up during active use") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 0.5 }
    mgr.startNewSession()

    for _ in 0..<5 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed in lastElapsed = elapsed }
    mgr.tick()

    assert(lastElapsed > 0, "Elapsed should be > 0 during active use, got \(lastElapsed)")
    assert(!mgr.isIdle, "Should not be idle when there is input activity")
}

test("Timer keeps counting when idle time is below threshold") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 10.0 } // 10s idle, well below 5min threshold
    mgr.startNewSession()

    for _ in 0..<5 {
        mgr.tick()
        Thread.sleep(forTimeInterval: 0.05)
    }

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed in lastElapsed = elapsed }
    mgr.tick()

    assert(lastElapsed > 0, "Timer should keep counting when idle < threshold, got \(lastElapsed)")
    assert(!mgr.isIdle, "Should not be idle")
}

test("Session ends when idle threshold exceeded") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { 301.0 } // Over 5min threshold
    mgr.startNewSession()

    var lastElapsed: TimeInterval = 0
    mgr.onUpdate = { _, elapsed in lastElapsed = elapsed }
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

test("No spurious resets during continuous activity (THE BUG)") {
    let mgr = SessionManager()
    mgr.idleTimeProvider = { Double.random(in: 0.0...1.5) }
    mgr.startNewSession()

    var sessionStateChanges = 0
    mgr.onSessionStateChanged = { sessionStateChanges += 1 }

    var elapsedValues: [TimeInterval] = []
    mgr.onUpdate = { _, elapsed in elapsedValues.append(elapsed) }

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

    // Go idle
    fakeIdleTime = 301.0
    mgr.tick()

    // Return from idle
    fakeIdleTime = 0.5
    mgr.tick()

    assert(sessionStateChanges == 2, "Expected 2 state changes (idle + return), got \(sessionStateChanges)")
    assert(!mgr.isIdle, "Should not be idle after returning")
}

// ─── Results ───

print("")
if failed == 0 {
    print("All \(passed) assertions passed ✓")
} else {
    print("\(failed) assertion(s) FAILED, \(passed) passed")
    exit(1)
}
