import Foundation

struct Preferences {
    private static let defaults = UserDefaults.standard

    enum Key: String, CaseIterable {
        case reminderEnabled
        case reminderIntervalMinutes
        case idleThresholdMinutes
        case showSeconds
        case awakeIndicatorStyle
        case customAwakeIndicator
        case defaultAwakeDurationMinutes
        // Break reminder indicators
        case reminderBannerEnabled
        case reminderSoundEnabled
        case reminderSoundName
        case reminderSoundVolume
        case reminderShakeEnabled
        case reminderShakeDuration
        case reminderShakeUntilClicked
        // Color indicators
        case colorBeforeBreakEnabled
        case colorBeforeBreak
        case colorAfterBreakEnabled
        case colorAfterBreak
    }

    // Preset indicator styles
    static let indicatorPresets: [(label: String, symbol: String)] = [
        ("Dot", "\u{25CF}"),       // ●
        ("Sun", "\u{2600}"),       // ☀
        ("Moon", "\u{263E}"),      // ☾
        ("Bolt", "\u{26A1}"),      // ⚡
        ("Star", "\u{2605}"),      // ★
        ("Eye", "\u{25C9}"),       // ◉
        ("Arrow", "\u{2191}"),     // ↑
        ("Flame", "\u{1F525}"),    // 🔥
        ("Coffee", "\u{2615}"),    // ☕
    ]

    /// The currently selected indicator index, or -1 for custom.
    static var awakeIndicatorIndex: Int {
        get { defaults.object(forKey: Key.awakeIndicatorStyle.rawValue) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.awakeIndicatorStyle.rawValue) }
    }

    /// Custom indicator string set by user.
    static var customAwakeIndicator: String {
        get { defaults.string(forKey: Key.customAwakeIndicator.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.customAwakeIndicator.rawValue) }
    }

    /// Resolved indicator to display.
    static var awakeIndicator: String {
        let idx = awakeIndicatorIndex
        if idx >= 0 && idx < indicatorPresets.count {
            return indicatorPresets[idx].symbol
        }
        let custom = customAwakeIndicator
        return custom.isEmpty ? "\u{25CF}" : custom
    }

    static var reminderEnabled: Bool {
        get { defaults.object(forKey: Key.reminderEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.reminderEnabled.rawValue) }
    }

    static var reminderIntervalMinutes: Double {
        get {
            let val = defaults.double(forKey: Key.reminderIntervalMinutes.rawValue)
            return val > 0 ? val : 20
        }
        set { defaults.set(newValue, forKey: Key.reminderIntervalMinutes.rawValue) }
    }

    static var idleThresholdMinutes: Int {
        get {
            let val = defaults.integer(forKey: Key.idleThresholdMinutes.rawValue)
            return val > 0 ? val : 5
        }
        set { defaults.set(newValue, forKey: Key.idleThresholdMinutes.rawValue) }
    }

    static var showSeconds: Bool {
        get { defaults.object(forKey: Key.showSeconds.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showSeconds.rawValue) }
    }

    static var defaultAwakeDurationMinutes: Int {
        get {
            let val = defaults.integer(forKey: Key.defaultAwakeDurationMinutes.rawValue)
            return val > 0 ? val : 300
        }
        set { defaults.set(newValue, forKey: Key.defaultAwakeDurationMinutes.rawValue) }
    }

    // MARK: - Break Reminder Indicators

    static var reminderBannerEnabled: Bool {
        get { defaults.object(forKey: Key.reminderBannerEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reminderBannerEnabled.rawValue) }
    }

    static var reminderSoundEnabled: Bool {
        get { defaults.object(forKey: Key.reminderSoundEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.reminderSoundEnabled.rawValue) }
    }

    static var reminderSoundName: String {
        get { defaults.string(forKey: Key.reminderSoundName.rawValue) ?? "Glass" }
        set { defaults.set(newValue, forKey: Key.reminderSoundName.rawValue) }
    }

    /// Sound volume 0.0–1.0
    static var reminderSoundVolume: Float {
        get {
            let val = defaults.float(forKey: Key.reminderSoundVolume.rawValue)
            return val > 0 ? val : 0.5
        }
        set { defaults.set(newValue, forKey: Key.reminderSoundVolume.rawValue) }
    }

    static var reminderShakeEnabled: Bool {
        get { defaults.object(forKey: Key.reminderShakeEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reminderShakeEnabled.rawValue) }
    }

    /// Shake mode: "0.4", "1", "2", "5", or "until_break"
    static var reminderShakeMode: String {
        get { defaults.string(forKey: Key.reminderShakeDuration.rawValue) ?? "0.4" }
        set { defaults.set(newValue, forKey: Key.reminderShakeDuration.rawValue) }
    }

    static var reminderShakeUntilBreak: Bool {
        reminderShakeMode == "until_break"
    }

    static var reminderShakeDuration: Double {
        Double(reminderShakeMode) ?? 0.4
    }

    // MARK: - Color Indicators

    static var colorBeforeBreakEnabled: Bool {
        get { defaults.object(forKey: Key.colorBeforeBreakEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.colorBeforeBreakEnabled.rawValue) }
    }

    /// Hex color string for "before break" color. Default green.
    static var colorBeforeBreak: String {
        get { defaults.string(forKey: Key.colorBeforeBreak.rawValue) ?? "#34C759" }
        set { defaults.set(newValue, forKey: Key.colorBeforeBreak.rawValue) }
    }

    static var colorAfterBreakEnabled: Bool {
        get { defaults.object(forKey: Key.colorAfterBreakEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.colorAfterBreakEnabled.rawValue) }
    }

    /// Hex color string for "after break" color. Default red.
    static var colorAfterBreak: String {
        get { defaults.string(forKey: Key.colorAfterBreak.rawValue) ?? "#FF3B30" }
        set { defaults.set(newValue, forKey: Key.colorAfterBreak.rawValue) }
    }

    // MARK: - Restore Defaults

    static func restoreDefaults() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: - System Sounds

    static var availableSystemSounds: [String] {
        let soundsDir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: soundsDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { $0.replacingOccurrences(of: ".aiff", with: "") }
            .sorted()
    }
}
