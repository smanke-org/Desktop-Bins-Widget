import AppKit

/// Menu bar entry point. The menu is rebuilt on open so its checkmarks and
/// counts always reflect current state.
///
/// The menu is for doing things; set-and-forget preferences (launch at login,
/// update checks, moving Desktop files, Command-drag to move) live only in
/// Settings. Listing every toggle here as well is what made the menu cluttered.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let panelController: BinPanelController
    private let settingsWindowController = SettingsWindowController()

    private static let iconSizes: [(String, Double)] = [
        ("Small Icons", 32),
        ("Medium Icons", 48),
        ("Large Icons", 64),
        ("Extra Large Icons", 96)
    ]

    init(panelController: BinPanelController) {
        self.panelController = panelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Desktop Bins Widget")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Bins
        menu.addItem(withTitle: "New Bin", action: #selector(newBin), keyEquivalent: "n", target: self)
        let visibilityTitle = panelController.isVisible ? "Hide All Bins" : "Show All Bins"
        menu.addItem(withTitle: visibilityTitle, action: #selector(toggleVisibility), keyEquivalent: "", target: self)
        menu.addItem(.separator())

        menu.addItem(submenuTitled: "View", viewMenu())
        menu.addItem(submenuTitled: "Tools", toolsMenu())
        menu.addItem(.separator())

        // App. A release found by the launch check is offered here rather than
        // prompted for, so an install only ever follows a click the user made.
        if let pending = UpdateAvailability.shared.pending {
            let updateItem = menu.addItem(withTitle: "Update to \(pending)…", action: #selector(checkForUpdates), keyEquivalent: "", target: self)
            updateItem.toolTip = "A newer release is available. Downloading and installing it needs your confirmation."
        } else {
            let updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "", target: self)
            updateItem.toolTip = "Download and install the latest release from GitHub, then restart."
        }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",", target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desktop Bins Widget", action: #selector(quit), keyEquivalent: "q", target: self)

        // Version last, as a non-actionable footer.
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "Desktop Bins Widget \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
    }

    /// Appearance tweaks made while looking at the bins, kept one click away.
    private func viewMenu() -> NSMenu {
        let settings = SettingsStore.shared
        let menu = NSMenu()
        for (name, value) in Self.iconSizes {
            let item = menu.addItem(withTitle: name, action: #selector(setIconSize(_:)), keyEquivalent: "", target: self)
            item.representedObject = value
            item.state = settings.iconSize == value ? .on : .off
        }
        menu.addItem(.separator())
        let labelsItem = menu.addItem(withTitle: "Show Labels", action: #selector(toggleLabels), keyEquivalent: "", target: self)
        labelsItem.state = settings.showLabels ? .on : .off
        return menu
    }

    /// Occasional maintenance and recovery, out of the way of everyday use.
    private func toolsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Bring All Bins to Main Display…", action: #selector(consolidate), keyEquivalent: "", target: self)
        menu.addItem(withTitle: "Remove Missing Items", action: #selector(removeMissing), keyEquivalent: "", target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Desktop Bins Folder", action: #selector(revealLocalFolder), keyEquivalent: "", target: self)
        menu.addItem(withTitle: "Return All Files to Desktop…", action: #selector(returnAllToDesktop), keyEquivalent: "", target: self)
        return menu
    }

    @objc private func newBin() { panelController.addBinAtCenterOfMainScreen() }
    @objc private func toggleLabels() { SettingsStore.shared.showLabels.toggle() }

    @objc private func revealLocalFolder() {
        let folder = LocalBinFolder.url
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    @objc private func returnAllToDesktop() {
        let confirm = NSAlert()
        confirm.messageText = "Return all files to the Desktop?"
        confirm.informativeText = "Every file a bin moved into the Desktop Bins folder goes back to the Desktop, which syncs it to your other computers again. The items stay in their bins."
        confirm.addButton(withTitle: "Return Files")
        confirm.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let result = panelController.returnAllFilesToDesktop()
        let alert = NSAlert()
        if result.failed.isEmpty {
            alert.messageText = result.returned == 0 ? "Nothing to return" : "Returned \(result.returned) file(s)"
            alert.informativeText = result.returned == 0
                ? "No bin is holding a file moved from the Desktop."
                : "They are back on the Desktop, and still in their bins."
        } else {
            alert.messageText = "Returned \(result.returned), couldn't return \(result.failed.count)"
            alert.informativeText = result.failed.joined(separator: "\n")
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleVisibility() { panelController.setAllVisible(!panelController.isVisible) }
    @objc private func checkForUpdates() { UpdateController.checkForUpdates() }
    @objc func showSettings() { settingsWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func setIconSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        SettingsStore.shared.iconSize = value
    }

    @objc private func consolidate() {
        let alert = NSAlert()
        alert.messageText = "Bring all bins to the main display?"
        alert.informativeText = "Every panel will be moved onto this display and re-pinned here. Use this if panels are stranded on a monitor that is no longer attached."
        alert.addButton(withTitle: "Bring Them Here")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let moved = panelController.consolidateBinsToMainDisplay()
        let done = NSAlert()
        done.messageText = "Moved \(moved) bin(s)"
        done.informativeText = "They are now on the main display and pinned to it."
        done.addButton(withTitle: "OK")
        done.runModal()
    }

    @objc private func removeMissing() {
        let removed = panelController.removeMissingItems()
        let alert = NSAlert()
        alert.messageText = removed == 0 ? "No missing items" : "Removed \(removed) missing item(s)"
        alert.informativeText = removed == 0
            ? "Every item in your bins still points at a file that exists."
            : "Those files no longer exist, so their shortcuts were cleared."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        addItem(item)
        return item
    }

    func addItem(submenuTitled title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
