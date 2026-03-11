import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var sessionManager: SessionManager!
    private var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        sessionManager = SessionManager()
        statusBarController = StatusBarController(sessionManager: sessionManager)
        statusBarController.onPreferences = { [weak self] in
            self?.showPreferences()
        }
        sessionManager.start()
        registerSleepWakeNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager.stop()
    }

    private func registerSleepWakeNotifications() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(systemWillSleep),
                         name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(systemDidWake),
                         name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidLock),
                         name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidUnlock),
                         name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        sessionManager.handleSleep()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        sessionManager.handleWake()
    }

    @objc private func screenDidLock(_ notification: Notification) {
        sessionManager.handleSleep()
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        sessionManager.handleWake()
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(sessionManager: sessionManager)
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
