import Cocoa

/// Application menus for the Dock app. The Dock icon, not a status item, brings a minimized holder back.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let holderManager: HolderManager
    private let showPicker: () -> Void
    private let holderMenu = NSMenu(title: "Holder")

    init(holderManager: HolderManager, showPicker: @escaping () -> Void) {
        self.holderManager = holderManager
        self.showPicker = showPicker
        super.init()
        holderMenu.delegate = self
        installMainMenu()
    }

    func revealFromDock() {
        NSApp.activate(ignoringOtherApps: true)
        holderManager.presentHolders()
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About WindowSnap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let choose = appMenu.addItem(withTitle: "Choose Apps…", action: #selector(chooseApps), keyEquivalent: "o")
        choose.target = self
        let show = appMenu.addItem(withTitle: "Show Holder", action: #selector(showHolder), keyEquivalent: "")
        show.target = self
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit WindowSnap", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        let holderItem = NSMenuItem()
        main.addItem(holderItem)
        holderItem.submenu = holderMenu

        NSApp.mainMenu = main
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === holderMenu else { return }
        holderManager.ensureMonitoring()
        menu.removeAllItems()

        let newItem = menu.addItem(withTitle: "New Holder", action: #selector(newHolder), keyEquivalent: "n")
        newItem.target = self

        let editTitle = holderManager.isEditing ? "Done Editing" : "Edit Holders"
        let editItem = menu.addItem(withTitle: editTitle, action: #selector(toggleEditing), keyEquivalent: "e")
        editItem.target = self
        editItem.state = holderManager.isEditing ? .on : .off

        let deleteItem = menu.addItem(withTitle: "Delete Selected Holder", action: #selector(deleteSelected), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = holderManager.canDeleteSelected

        if !WindowTracker.isTrusted {
            menu.addItem(.separator())
            let reopen = menu.addItem(withTitle: "Reopen to Apply Access", action: #selector(reopenToApply), keyEquivalent: "")
            reopen.target = self
            let access = menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(promptAccess), keyEquivalent: "")
            access.target = self
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func chooseApps() {
        showPicker()
    }

    @objc private func showHolder() {
        revealFromDock()
    }

    @objc private func newHolder() {
        holderManager.createHolder()
    }

    @objc private func toggleEditing() {
        holderManager.toggleEditing()
    }

    @objc private func deleteSelected() {
        holderManager.deleteSelected()
    }

    @objc private func promptAccess() {
        WindowTracker.openAccessibilitySettings()
    }

    @objc private func reopenToApply() {
        WindowTracker.relaunchToApplyTrust()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
