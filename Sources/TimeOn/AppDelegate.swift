import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var sessionManager: SessionManager!
    private var preferencesWindow: PreferencesWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.configure()
        NotificationManager.shared.requestAuthorization()
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func registerSleepWakeNotifications() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(systemWillSleep),
                         name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(systemDidWake),
                         name: NSWorkspace.didWakeNotification, object: nil)

        // Screen lock/unlock are distributed notifications, not NSWorkspace
        // session-active notifications (those fire on fast user switching).
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
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

    private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(sessionManager: sessionManager)
            preferencesWindow?.onPreviewPopup = { [weak self] content in
                self?.statusBarController.showBadge(content)
            }
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
