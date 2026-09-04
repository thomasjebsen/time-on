import Foundation
import UserNotifications
import os

/// Single owner of all UserNotifications usage: authorization, delivery, and the
/// center delegate. Every failure is logged (subsystem "com.timeon.app", category
/// "notifications") and kept in `lastError` so Settings can show why banners are
/// not appearing instead of failing silently.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let log = Logger(subsystem: "com.timeon.app", category: "notifications")
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// Most recent authorization or delivery error, if any. Main-thread only.
    private(set) var lastError: Error?

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Installs the center delegate so banners are presented even while Time On is
    /// the active app. Call once, early in app launch, before requesting authorization.
    func configure() {
        center.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization(completion: ((Bool, Error?) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.lastError = error
                    self.log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
                } else if granted {
                    self.lastError = nil
                    self.log.info("Notification authorization granted")
                } else {
                    self.log.error("Notification authorization denied by user")
                }
                completion?(granted, error)
            }
        }
    }

    /// Requests permission if it has never been asked. Calls `onDenied` (on main) when
    /// the user has declined, either now or previously; `completion` always runs (on
    /// main) once the flow has settled, so callers can refresh any status display.
    func ensureAuthorized(onDenied: @escaping () -> Void, completion: (() -> Void)? = nil) {
        fetchStatus { [weak self] status, _ in
            switch status {
            case .notDetermined:
                self?.requestAuthorization { granted, _ in
                    if !granted { onDenied() }
                    completion?()
                }
            case .denied:
                onDenied()
                completion?()
            default:
                completion?()
            }
        }
    }

    /// Current authorization status plus the last recorded error, delivered on main.
    func fetchStatus(_ completion: @escaping (UNAuthorizationStatus, Error?) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.log.debug("authorizationStatus = \(settings.authorizationStatus.rawValue)")
                completion(settings.authorizationStatus, self?.lastError)
            }
        }
    }

    // MARK: - Delivery

    /// Posts a banner immediately. Sound is intentionally nil: the app plays its own
    /// sound via NSSound so banner and sound can be configured independently.
    func send(title: String, body: String, identifierPrefix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        center.add(request) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.lastError = error
                    self.log.error("Notification '\(title, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    self.lastError = nil
                    self.log.info("Notification '\(title, privacy: .public)' handed to Notification Center")
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, macOS drops banners while the app is frontmost (for example right
    /// after opening Settings or History, which activate the app).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
