import Foundation
import IOKit.pwr_mgt

final class CaffeineManager {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false
    private var deactivationTimer: Timer?

    var onStateChanged: ((Bool) -> Void)?

    /// Remaining seconds if a timed activation is running, nil if indefinite or inactive.
    private(set) var remainingSeconds: Int?

    var isAwake: Bool { isActive }

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(duration: nil)
        }
    }

    func activate(duration: TimeInterval?) {
        if isActive { deactivate() }

        let reason = "Time On keeping display awake" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if success == kIOReturnSuccess {
            isActive = true

            if let duration = duration {
                remainingSeconds = Int(duration)
                deactivationTimer?.invalidate()
                deactivationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    guard let self = self else { timer.invalidate(); return }
                    if let remaining = self.remainingSeconds {
                        if remaining <= 1 {
                            self.deactivate()
                        } else {
                            self.remainingSeconds = remaining - 1
                            self.onStateChanged?(true)
                        }
                    }
                }
                RunLoop.main.add(deactivationTimer!, forMode: .common)
            } else {
                remainingSeconds = nil
            }

            onStateChanged?(true)
        }
    }

    func deactivate() {
        if isActive {
            IOPMAssertionRelease(assertionID)
            isActive = false
            assertionID = 0
        }
        deactivationTimer?.invalidate()
        deactivationTimer = nil
        remainingSeconds = nil
        onStateChanged?(false)
    }

    deinit {
        deactivate()
    }

    static let durations: [(title: String, seconds: TimeInterval?)] = [
        ("5 minutes", 5 * 60),
        ("10 minutes", 10 * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("5 hours", 5 * 60 * 60),
        ("Indefinitely", nil),
    ]
}
