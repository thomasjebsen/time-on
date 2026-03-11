import Foundation
import IOKit

struct IdleDetector {
    /// Returns the number of seconds since the last user input event (mouse/keyboard).
    static func systemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return 0 }

        let entry = IOIteratorNext(iterator)
        defer { IOObjectRelease(entry) }
        guard entry != 0 else { return 0 }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedDict,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else { return 0 }

        guard let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleTime = dict["HIDIdleTime"] as? Int64 else { return 0 }

        return TimeInterval(idleTime) / 1_000_000_000
    }
}
