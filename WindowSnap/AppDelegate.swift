import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var holderManager: HolderManager!
    private var menuBarController: MenuBarController!
    private var picker: PickerWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        holderManager = HolderManager()
        picker = PickerWindowController(holderManager: holderManager)
        menuBarController = MenuBarController(holderManager: holderManager) { [weak self] in
            self?.picker.show()
        }
        holderManager.start()
        picker.show()

        DispatchQueue.main.async {
            WindowTracker.promptForTrustIfNeeded()
            self.holderManager.ensureMonitoring()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if holderManager.hasHiddenHolder {
            menuBarController.revealFromDock()
        } else {
            picker.show()
        }
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
