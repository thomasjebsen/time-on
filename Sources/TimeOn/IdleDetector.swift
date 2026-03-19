import CoreGraphics
import Foundation

struct IdleDetector {
    /// Returns the number of seconds since the last user input event (mouse/keyboard/trackpad).
    /// Uses CoreGraphics CGEventSource which reliably tracks all HID input on modern macOS.
    static func systemIdleTime() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .keyDown,
            .scrollWheel,
            .leftMouseDragged,
            .rightMouseDragged,
        ]

        var minIdle = Double.greatestFiniteMagnitude
        for eventType in eventTypes {
            let idle = CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: eventType
            )
            if idle < minIdle {
                minIdle = idle
            }
        }

        return minIdle == Double.greatestFiniteMagnitude ? 0 : minIdle
    }
}
