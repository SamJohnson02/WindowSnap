import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var holderManager: HolderManager!
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        holderManager = HolderManager()
        menuBarController = MenuBarController(holderManager: holderManager)
        holderManager.start()
        if holderManager.holders.isEmpty {
            holderManager.createHolder()
        }

        DispatchQueue.main.async {
            WindowTracker.promptForTrustIfNeeded()
            self.holderManager.ensureMonitoring()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController.revealFromDock()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
enum WindowSnapMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
