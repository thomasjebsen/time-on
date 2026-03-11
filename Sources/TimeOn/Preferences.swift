import Foundation

struct Preferences {
    private static let defaults = UserDefaults.standard

    enum Key: String {
        case reminderEnabled
        case reminderIntervalMinutes
        case idleThresholdMinutes
        case showSeconds
        case awakeIndicatorStyle
        case customAwakeIndicator
        case defaultAwakeDurationMinutes
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
        get { defaults.object(forKey: Key.reminderEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reminderEnabled.rawValue) }
    }

    static var reminderIntervalMinutes: Int {
        get {
            let val = defaults.integer(forKey: Key.reminderIntervalMinutes.rawValue)
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
            return val > 0 ? val : 60
        }
        set { defaults.set(newValue, forKey: Key.defaultAwakeDurationMinutes.rawValue) }
    }
}
