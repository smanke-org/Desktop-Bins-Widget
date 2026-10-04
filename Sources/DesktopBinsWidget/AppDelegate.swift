import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: BinStore!
    private var panelController: BinPanelController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app; it has a Dock icon only if the user turned one on.
        NSApp.setActivationPolicy(AppPresence.showInDock ? .regular : .accessory)
        NSApp.mainMenu = AppPresence.mainMenu(appName: "Desktop Bins Widget", settingsTitle: "Settings…",
                                           target: self, settings: #selector(showSettings))

        store = BinStore()
        panelController = BinPanelController(store: store)
        statusItemController = StatusItemController(panelController: panelController)

        if store.bins.isEmpty {
            panelController.addBinAtCenterOfMainScreen()
        }

        scheduleLaunchUpdateCheck()
    }

    /// Looks for a newer release shortly after launch rather than during it,
    /// so startup isn't waiting on the network. Silent unless there is
    /// something to offer.
    private func scheduleLaunchUpdateCheck() {
        guard SettingsStore.shared.checkForUpdatesAtLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            UpdateController.checkForUpdates(silent: true)
        }
    }

    /// The Dock icon's right-click menu, when "Show in Dock" is on.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        AppPresence.dockMenu(title: "Settings…", target: self, action: #selector(showSettings))
    }

    /// Clicking the Dock icon, or opening the app again from Applications or
    /// Spotlight, opens Settings — the way back when both icons are hidden.
    /// Always, not only when no window is visible: the bins themselves are
    /// windows and are usually on screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showSettings() {
        statusItemController.showSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
