import Cocoa

/// A selectable animated menu-bar indicator for the Pomodoro timer.
///
/// Frame sets are adapted from the `cli-spinners` project
/// (https://github.com/sindresorhus/cli-spinners, MIT), plus a bespoke
/// opacity-fade "pulse" that renders via an animated text alpha rather than a
/// glyph cycle.
struct PomodoroIndicator {
    enum Kind {
        case pulse                  // ●/○ with an animated opacity fade
        case staticDot              // ● steady, tinted by phase
        case classic                // 🍅 / ☕ (the original)
        case frames([String])       // monochrome glyph cycle (tinted by phase)
        case emojiFrames([String])  // emoji glyph cycle (not tinted; no phase distinction)
    }

    let id: String
    let name: String
    let kind: Kind
    let interval: TimeInterval      // seconds per frame (frame cycles only)

    /// Whether this style needs a repeating redraw timer.
    var isAnimated: Bool {
        switch kind {
        case .staticDot, .classic: return false
        default: return true
        }
    }

    /// The glyph to display at animation time `t` for the given phase.
    func glyph(at t: TimeInterval, isWork: Bool) -> String {
        switch kind {
        case .pulse: return isWork ? "\u{25CF}" : "\u{25CB}"   // ● / ○
        case .staticDot:
            let custom = Preferences.pomodoroStaticIcon
            return custom.isEmpty ? "\u{25CF}" : custom        // user-chosen glyph, default ●
        case .classic: return isWork ? "\u{1F345}" : "\u{2615}" // 🍅 / ☕
        case .frames(let f): return f[frameIndex(t, count: f.count)]
        case .emojiFrames(let f): return f[frameIndex(t, count: f.count)]
        }
    }

    /// Whether this style is tinted by the user's work/break color (monochrome
    /// glyphs). Emoji and Classic carry their own color, so they are never tinted.
    var usesColor: Bool {
        switch kind {
        case .emojiFrames, .classic: return false
        default: return true
        }
    }

    private func phaseColor(isWork: Bool) -> NSColor {
        let hex = isWork ? Preferences.pomodoroWorkColor : Preferences.pomodoroBreakColor
        return NSColor(hex: hex) ?? (isWork ? .systemOrange : .systemTeal)
    }

    /// The glyph's foreground color at time `t`, or `nil` to inherit the title color.
    func color(at t: TimeInterval, isWork: Bool) -> NSColor? {
        switch kind {
        case .pulse:
            // Smooth opacity breath, ~1.4s per cycle, in the chosen phase color.
            let phase = (sin(t / 1.4 * 2 * .pi) + 1) / 2          // 0…1
            return phaseColor(isWork: isWork).withAlphaComponent(CGFloat(0.2 + 0.8 * phase))
        case .staticDot, .frames:
            return phaseColor(isWork: isWork)
        case .emojiFrames, .classic:
            return nil
        }
    }

    private func frameIndex(_ t: TimeInterval, count: Int) -> Int {
        guard interval > 0, count > 0 else { return 0 }
        return Int(t / interval) % count
    }

    // MARK: - Catalog

    static let all: [PomodoroIndicator] = [
        .init(id: "pulse",      name: "Pulse",       kind: .pulse, interval: 0),
        .init(id: "breathing",  name: "Breathing",   kind: .frames(["\u{00B7}", "\u{2218}", "\u{25CB}", "\u{25D4}", "\u{25D1}", "\u{25D5}", "\u{25CF}", "\u{25D5}", "\u{25D1}", "\u{25D4}", "\u{25CB}", "\u{2218}"]), interval: 0.13),
        .init(id: "dots",       name: "Dots",        kind: .frames(["\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}"]), interval: 0.08),
        .init(id: "blocks",     name: "Blocks",      kind: .frames(["\u{28FE}", "\u{28FD}", "\u{28FB}", "\u{28BF}", "\u{287F}", "\u{28DF}", "\u{28EF}", "\u{28F7}"]), interval: 0.08),
        .init(id: "halfCircle", name: "Half circle", kind: .frames(["\u{25D0}", "\u{25D3}", "\u{25D1}", "\u{25D2}"]), interval: 0.1),
        .init(id: "quarter",    name: "Quarter",     kind: .frames(["\u{25F4}", "\u{25F7}", "\u{25F6}", "\u{25F5}"]), interval: 0.12),
        .init(id: "arc",        name: "Arc",         kind: .frames(["\u{25DC}", "\u{25E0}", "\u{25DD}", "\u{25DE}", "\u{25E1}", "\u{25DF}"]), interval: 0.1),
        .init(id: "line",       name: "Line",        kind: .frames(["-", "\\", "|", "/"]), interval: 0.13),
        .init(id: "star",       name: "Star",        kind: .frames(["\u{2736}", "\u{2738}", "\u{2739}", "\u{273A}", "\u{2739}", "\u{2737}"]), interval: 0.07),
        .init(id: "bounce",     name: "Bounce",      kind: .frames(["\u{2801}", "\u{2802}", "\u{2804}", "\u{2802}"]), interval: 0.12),
        .init(id: "bars",       name: "Bars",        kind: .frames(["\u{2581}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2586}", "\u{2585}", "\u{2584}", "\u{2583}"]), interval: 0.12),
        .init(id: "moon",       name: "Moon",        kind: .emojiFrames(["\u{1F311}", "\u{1F312}", "\u{1F313}", "\u{1F314}", "\u{1F315}", "\u{1F316}", "\u{1F317}", "\u{1F318}"]), interval: 0.12),
        .init(id: "clock",      name: "Clock",       kind: .emojiFrames(["\u{1F55B}", "\u{1F550}", "\u{1F551}", "\u{1F552}", "\u{1F553}", "\u{1F554}", "\u{1F555}", "\u{1F556}", "\u{1F557}", "\u{1F558}", "\u{1F559}", "\u{1F55A}"]), interval: 0.1),
        .init(id: "classic",    name: "Classic",     kind: .classic, interval: 0),
        .init(id: "static",     name: "Static",      kind: .staticDot, interval: 0),
    ]

    static func style(for id: String) -> PomodoroIndicator {
        all.first { $0.id == id } ?? all[0]
    }

    /// Wall-clock time scaled by the user's speed preference. A larger speed
    /// value stretches time (slower animation); this feeds both the frame index
    /// and the pulse breath, so one control governs every style's pace.
    static func animationClock() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate / max(0.1, Preferences.pomodoroIndicatorSpeed)
    }

    /// Speed presets shown in Settings: (label, multiplier). Larger = slower.
    /// Calibrated so the previous "Very slow" (2.5×) is now "Fast", with slower
    /// options beyond; "Custom…" in the UI allows any value in between.
    static let speedPresets: [(label: String, value: Double)] = [
        ("Very fast", 1.5),
        ("Fast", 2.5),
        ("Normal", 4.0),
        ("Slow", 6.0),
        ("Very slow", 10.0),
    ]
}
