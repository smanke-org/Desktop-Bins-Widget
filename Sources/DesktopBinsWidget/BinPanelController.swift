import AppKit

/// Owns one window per bin and handles every panel action.
final class BinPanelController: NSObject, BinPanelViewDelegate {
    private let store: BinStore
    private var windows: [UUID: BinPanelWindow] = [:]
    private var expandedHeights: [UUID: Double] = [:]
    private var gestureStartFrame: NSRect?
    private var gestureDidDrag = false
    private var screenSettleWorkItems: [DispatchWorkItem] = []
    private var strayMoveWorkItem: DispatchWorkItem?
    private var strayMoveRestores = 0
    private(set) var isVisible = true

    private var minWidth: CGFloat { CGFloat(SettingsStore.shared.minPanelWidth) }
    private var minHeight: CGFloat { CGFloat(SettingsStore.shared.minPanelHeight) }

    init(store: BinStore) {
        self.store = store
        super.init()
        store.onChange = { [weak self] in self?.syncWindows() }
        SettingsStore.shared.onChange = { [weak self] in self?.redrawAll() }
        pruneWakeTransientLayoutsOnce()
        syncWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Displays can come back after the last screen-parameters change of a
        // wake has already been handled, so a wake gets its own placement pass.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenConfigurationChanged),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenConfigurationChanged),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        adoptCurrentDisplayForUnpinnedBins()
        repairLegacyHiddenItems()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Display changes only move windows; they never save a position. Waking
    /// from sleep reconnects monitors one at a time, and saving the partial
    /// sets it passes through is what used to shift bins around their own
    /// screen. Positions are saved only when the user moves, resizes,
    /// collapses or gathers a bin. The burst of notifications is followed by
    /// further placements once it settles.
    @objc private func screenConfigurationChanged() {
        syncWindows()
        screenSettleWorkItems.forEach { $0.cancel() }
        screenSettleWorkItems = [1.5, 5, 15].map { delay in
            let work = DispatchWorkItem { [weak self] in
                self?.strayMoveRestores = 0
                self?.syncWindows()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// A bin window moved or resized without the user dragging it. macOS
    /// relocates windows while displays come and go, and after a wake it can
    /// put them back where *it* remembers them — sometimes well after the last
    /// display notification, so nothing re-placed the bin and it sat shifted.
    /// The saved position is the truth: put the window back, once things are
    /// quiet, and never save the stray frame.
    @objc private func binWindowFrameChanged(_ note: Notification) {
        guard let window = note.object as? BinPanelWindow,
              windows.values.contains(where: { $0 === window }) else { return }
        strayMoveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restoreStrayWindows() }
        strayMoveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func restoreStrayWindows() {
        // The user is mid-drag; their gesture decides where the bin goes.
        guard gestureStartFrame == nil else { return }
        for bin in store.bins {
            guard let window = windows[bin.id] else { continue }
            let expected = frameOf(bin)
            let actual = window.frame
            let off = abs(actual.minX - expected.minX) + abs(actual.minY - expected.minY)
                + abs(actual.width - expected.width) + abs(actual.height - expected.height)
            guard off > 1 else { continue }
            // Something that keeps fighting back must not become a loop.
            guard strayMoveRestores < 20 else {
                NSLog("DesktopBinsWidget: \(bin.title) keeps being moved to \(NSStringFromRect(actual)); leaving it until displays change")
                return
            }
            strayMoveRestores += 1
            NSLog("DesktopBinsWidget: \(bin.title) was moved to \(NSStringFromRect(actual)) without a drag; restoring \(NSStringFromRect(expected)) (displays: \(DisplaySnapshot.signature(of: DisplaySnapshot.current())))")
            window.setFrame(expected, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: expected.size)
            window.contentView?.needsDisplay = true
        }
    }

    // MARK: - Windows

    func syncWindows() {
        let currentIDs = Set(store.bins.map(\.id))
        for (id, window) in windows where !currentIDs.contains(id) {
            NotificationCenter.default.removeObserver(self, name: nil, object: window)
            window.close()
            windows.removeValue(forKey: id)
        }

        for bin in store.bins {
            let window: BinPanelWindow
            if let existing = windows[bin.id] {
                window = existing
                (window.contentView as? BinPanelView)?.bin = bin
            } else {
                window = makeWindow(for: bin)
                windows[bin.id] = window
            }

            let frame = frameOf(bin)
            window.setFrame(frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
            window.contentView?.needsDisplay = true
            if isVisible { window.orderFront(nil) }
        }
    }

    private func makeWindow(for bin: Bin) -> BinPanelWindow {
        let frame = frameOf(bin)
        let window = BinPanelWindow(contentRect: frame)
        let view = BinPanelView(bin: bin)
        view.delegate = self
        view.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = view
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(binWindowFrameChanged(_:)), name: name, object: window
            )
        }
        return window
    }

    private func redrawAll() {
        for window in windows.values {
            window.contentView?.needsDisplay = true
        }
    }

    private func view(for id: UUID) -> BinPanelView? {
        windows[id]?.contentView as? BinPanelView
    }

    /// Pushes a changed bin into both the store and the on-screen view.
    private func commit(_ bin: Bin) {
        store.updateBin(bin)
        view(for: bin.id)?.bin = bin
    }

    // MARK: - Display placement

    /// Where a bin belongs right now. The rules live in `BinPlacementResolver`
    /// so they can be tested against any monitor arrangement.
    private func frameOf(_ bin: Bin) -> NSRect {
        BinPlacementResolver.frame(for: bin, displays: DisplaySnapshot.current())
    }

    private func mainScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Emergency escape hatch: gathers every panel onto the main display and
    /// re-pins it there, for when panels are stranded on a monitor that no
    /// longer exists.
    @discardableResult
    func consolidateBinsToMainDisplay() -> Int {
        guard let screen = mainScreen() else { return 0 }
        let bounds = screen.visibleFrame
        let padding: CGFloat = 20
        var cursor = NSPoint(x: bounds.minX + padding, y: bounds.maxY - padding)
        var rowHeight: CGFloat = 0
        var moved = 0

        for var bin in store.bins {
            let width = min(CGFloat(bin.width), bounds.width - 2 * padding)
            let height = min(CGFloat(bin.height), bounds.height - 2 * padding)

            // Tile left to right, wrapping to a new row when out of width.
            if cursor.x + width > bounds.maxX - padding {
                cursor.x = bounds.minX + padding
                cursor.y -= rowHeight + padding
                rowHeight = 0
            }
            if cursor.y - height < bounds.minY + padding {
                cursor = NSPoint(x: bounds.minX + padding, y: bounds.maxY - padding)
                rowHeight = 0
            }

            let frame = NSRect(x: cursor.x, y: cursor.y - height, width: width, height: height)
            pinToDisplay(&bin, frame: frame)
            store.updateBin(bin)

            cursor.x += width + padding
            rowHeight = max(rowHeight, height)
            moved += 1
        }

        syncWindows()
        return moved
    }

    private func pinToDisplay(_ bin: inout Bin, frame: NSRect) {
        bin.x = Double(frame.origin.x)
        bin.y = Double(frame.origin.y)
        bin.width = Double(frame.width)
        bin.height = Double(frame.height)

        guard let screen = DisplayIdentity.screen(containing: frame),
              let uuid = DisplayIdentity.uuid(for: screen) else {
            bin.displayUUID = nil
            bin.relativeX = nil
            bin.relativeY = nil
            return
        }
        bin.displayUUID = uuid
        bin.relativeX = Double(frame.origin.x - screen.frame.origin.x)
        bin.relativeY = Double(frame.origin.y - screen.frame.origin.y)

        // Remember this arrangement against the current set of monitors.
        bin.layouts[DisplaySnapshot.signature(of: DisplaySnapshot.current())] = BinPlacement(
            displayUUID: uuid,
            relativeX: Double(frame.origin.x - screen.frame.origin.x),
            relativeY: Double(frame.origin.y - screen.frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        )
    }

    private static let prunedWakeLayoutsKey = "prunedWakeTransientLayouts"

    /// One-time cleanup of the positions versions before 1.1.15 saved while
    /// monitors reconnected after sleep (see
    /// `BinPlacementResolver.wakeTransientSignatures`). Runs once rather than
    /// every launch: from now on a partial monitor set only gets a layout when
    /// the user arranges a bin under it, and that must be kept.
    private func pruneWakeTransientLayoutsOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.prunedWakeLayoutsKey) else { return }
        for var bin in store.bins {
            let stale = BinPlacementResolver.wakeTransientSignatures(in: bin)
            guard !stale.isEmpty else { continue }
            stale.forEach { bin.layouts.removeValue(forKey: $0) }
            store.updateBin(bin)
            NSLog("DesktopBinsWidget: removed \(stale.count) layout(s) saved during wake for \(bin.title)")
        }
        defaults.set(true, forKey: Self.prunedWakeLayoutsKey)
    }

    private func adoptCurrentDisplayForUnpinnedBins() {
        for var bin in store.bins where bin.displayUUID == nil {
            pinToDisplay(&bin, frame: NSRect(x: bin.x, y: bin.y, width: bin.width, height: bin.height))
            if bin.displayUUID != nil { store.updateBin(bin) }
        }
    }

    // MARK: - Bin lifecycle

    func addBinAtCenterOfMainScreen() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 320, height: 260)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let colors = ["3B82F6", "10B981", "F59E0B", "EF4444", "8B5CF6", "EC4899"]
        var bin = Bin(
            title: "New Bin",
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height),
            colorHex: colors[store.bins.count % colors.count]
        )
        pinToDisplay(&bin, frame: frame)
        store.addBin(bin)
    }

    func setAllVisible(_ visible: Bool) {
        isVisible = visible
        for window in windows.values {
            visible ? window.orderFront(nil) : window.orderOut(nil)
        }
    }

    /// Drops items whose underlying file no longer exists, across all bins.
    @discardableResult
    func removeMissingItems() -> Int {
        var removed = 0
        for var bin in store.bins {
            let before = bin.items.count
            bin.items.removeAll { $0.isMissing }
            removed += before - bin.items.count
            if bin.items.count != before { commit(bin) }
        }
        return removed
    }


    // MARK: - Moving Desktop files

    /// Builds the item for a dropped file, moving it off the Desktop into
    /// `~/Desktop Bins` when the setting allows. A file that cannot be moved
    /// is still added, as a plain reference, so a drop never loses anything.
    private func makeItem(forDropped url: URL) -> (item: BinItem, failure: Error?) {
        guard SettingsStore.shared.moveDesktopFiles, LocalBinFolder.isOnDesktop(url) else {
            return (BinItem(url: url), nil)
        }
        do {
            let moved = try LocalBinFolder.moveIn(url)
            return (BinItem(url: moved, desktopName: url.lastPathComponent), nil)
        } catch {
            return (BinItem(url: url), error)
        }
    }

    /// Sends a moved file back to the Desktop as its item leaves a bin.
    ///
    /// If another bin still holds the same file it stays where it is, and
    /// that bin takes over returning it later. Throws if the move fails, so
    /// callers keep the item rather than stranding its file out of sight.
    private func release(_ item: BinItem, leaving binID: UUID) throws {
        guard let name = item.desktopName, let url = item.resolveURL() else { return }
        for var other in store.bins where other.id != binID {
            if let index = other.items.firstIndex(where: { $0.resolveURL()?.path == url.path }) {
                other.items[index].desktopName = name
                commit(other)
                return
            }
        }
        _ = try LocalBinFolder.moveToDesktop(url, name: name)
    }

    /// Safety valve: puts every moved file back on the Desktop. Items stay in
    /// their bins, now pointing at the Desktop copy. Returns how many were
    /// returned and the names of any that could not be.
    func returnAllFilesToDesktop() -> (returned: Int, failed: [String]) {
        var returned = 0
        var failed: [String] = []
        for var bin in store.bins {
            var changed = false
            for index in bin.items.indices {
                guard let name = bin.items[index].desktopName else { continue }
                guard let url = bin.items[index].resolveURL() else {
                    bin.items[index].desktopName = nil
                    changed = true
                    continue
                }
                do {
                    let back = try LocalBinFolder.moveToDesktop(url, name: name)
                    bin.items[index].relocate(to: back)
                    bin.items[index].desktopName = nil
                    returned += 1
                    changed = true
                } catch {
                    NSLog("DesktopBinsWidget: could not return \(name) to the Desktop: \(error)")
                    failed.append(name)
                }
            }
            if changed { commit(bin) }
        }
        return (returned, failed)
    }

    /// One-time repair for Desktop files that versions before 1.1.8 marked
    /// hidden. The flag synced through OneDrive and left invisible files on
    /// other computers. Each is moved into `~/Desktop Bins` as if it had just
    /// been dropped — which takes it off every other Desktop — and unhidden
    /// wherever it ends up.
    private func repairLegacyHiddenItems() {
        for var bin in store.bins {
            var changed = false
            for index in bin.items.indices where bin.items[index].didHideOriginal {
                bin.items[index].didHideOriginal = false
                changed = true
                guard var url = bin.items[index].resolveURL() else { continue }

                if SettingsStore.shared.moveDesktopFiles, LocalBinFolder.isOnDesktop(url) {
                    do {
                        let moved = try LocalBinFolder.moveIn(url)
                        bin.items[index].relocate(to: moved)
                        bin.items[index].desktopName = url.lastPathComponent
                        url = moved
                    } catch {
                        NSLog("DesktopBinsWidget: could not move \(url.lastPathComponent) off the Desktop: \(error)")
                    }
                }

                var values = URLResourceValues()
                values.isHidden = false
                do {
                    try url.setResourceValues(values)
                } catch {
                    NSLog("DesktopBinsWidget: could not unhide \(url.lastPathComponent): \(error)")
                }
            }
            if changed { commit(bin) }
        }
    }

    private func presentMoveFailure(_ message: String, names: [String]) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = names.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - BinPanelViewDelegate

    func panelDidBeginGesture(_ view: BinPanelView, kind: BinPanelView.GestureKind) {
        gestureStartFrame = windows[view.bin.id]?.frame
        gestureDidDrag = false
    }

    func panel(_ view: BinPanelView, didDragBy delta: CGSize, kind: BinPanelView.GestureKind) {
        guard let window = windows[view.bin.id] else { return }
        let frame = window.frame
        if delta != .zero { gestureDidDrag = true }

        switch kind {
        case .move:
            window.setFrameOrigin(NSPoint(x: frame.origin.x + delta.width, y: frame.origin.y + delta.height))
        case .resize:
            let width = max(minWidth, frame.width + delta.width)
            let height = max(minHeight, frame.height - delta.height)
            window.setFrame(
                NSRect(x: frame.origin.x, y: frame.maxY - height, width: width, height: height),
                display: true
            )
            window.contentView?.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            window.contentView?.needsDisplay = true
        }
    }

    func panelDidEndGesture(_ view: BinPanelView) {
        gestureStartFrame = nil
        // A click on the title bar or an empty spot is not a move. Saving here
        // anyway would make permanent wherever macOS had left the window.
        guard gestureDidDrag else {
            restoreStrayWindows()
            return
        }
        gestureDidDrag = false
        guard var bin = store.bin(for: view.bin.id), let window = windows[bin.id] else { return }
        pinToDisplay(&bin, frame: window.frame)
        commit(bin)
    }

    func panelRequestsToggleCollapse(_ view: BinPanelView) {
        guard var bin = store.bin(for: view.bin.id), let window = windows[bin.id] else { return }
        let frame = window.frame
        bin.isCollapsed.toggle()

        let newHeight: CGFloat
        if bin.isCollapsed {
            expandedHeights[bin.id] = Double(frame.height)
            newHeight = WidgetMetrics.titleBarHeight
        } else {
            newHeight = CGFloat(expandedHeights[bin.id] ?? 260)
        }

        let newFrame = NSRect(x: frame.minX, y: frame.maxY - newHeight, width: frame.width, height: newHeight)
        pinToDisplay(&bin, frame: newFrame)
        window.setFrame(newFrame, display: true)
        window.contentView?.frame = NSRect(origin: .zero, size: newFrame.size)
        commit(bin)
    }

    func panel(_ view: BinPanelView, didDropURLs urls: [URL], atIndex index: Int) {
        guard var bin = store.bin(for: view.bin.id) else { return }
        // Ignore anything already held, so dropping twice doesn't duplicate.
        let existing = Set(bin.items.map(\.path))
        var newItems: [BinItem] = []
        var failed: [String] = []
        for url in urls where !existing.contains(url.path) {
            let result = makeItem(forDropped: url)
            newItems.append(result.item)
            if let error = result.failure {
                NSLog("DesktopBinsWidget: could not move \(url.lastPathComponent) off the Desktop: \(error)")
                failed.append(url.lastPathComponent)
            }
        }
        guard !newItems.isEmpty else { return }

        let insertAt = min(max(index, 0), bin.items.count)
        bin.items.insert(contentsOf: newItems, at: insertAt)
        commit(bin)

        if !failed.isEmpty {
            presentMoveFailure("Couldn't move some items off the Desktop",
                               names: failed + ["", "They were added to the bin but are still on the Desktop."])
        }
    }

    func panel(_ view: BinPanelView, didReorderFrom oldIndex: Int, to newIndex: Int) {
        guard var bin = store.bin(for: view.bin.id),
              bin.items.indices.contains(oldIndex) else { return }
        let item = bin.items.remove(at: oldIndex)
        bin.items.insert(item, at: min(max(newIndex, 0), bin.items.count))
        commit(bin)
    }

    func panel(_ view: BinPanelView, didOpenItemAt index: Int) {
        guard let bin = store.bin(for: view.bin.id), bin.items.indices.contains(index) else { return }
        guard let url = bin.items[index].resolvedTargetURL() else {
            presentMissingItemAlert(name: bin.items[index].displayName)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func presentMissingItemAlert(name: String) {
        let alert = NSAlert()
        alert.messageText = "“\(name)” can’t be found"
        alert.informativeText = "The file may have been deleted or moved to a location Desktop Bins Widget can't follow."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menus

    func panelContextMenu(_ view: BinPanelView, forItemAt index: Int?) -> NSMenu {
        let menu = NSMenu()
        let id = view.bin.id
        guard let bin = store.bin(for: id) else { return menu }

        if let index, bin.items.indices.contains(index) {
            let item = bin.items[index]
            menu.addItem(withActionTitle: "Open “\(item.displayName)”") { [weak self] in
                guard let self, let view = self.view(for: id) else { return }
                self.panel(view, didOpenItemAt: index)
            }
            menu.addItem(withActionTitle: "Reveal in Finder") { [weak self] in
                // Reveal the real item rather than an alias pointing at it.
                guard let url = self?.store.bin(for: id)?.items[safe: index]?.resolvedTargetURL() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            menu.addItem(withActionTitle: "Remove from Bin") { [weak self] in
                guard let self, var bin = self.store.bin(for: id), bin.items.indices.contains(index) else { return }
                let removed = bin.items[index]
                // A file this app moved off the Desktop goes back there as it
                // leaves the bin. If that fails it stays in the bin, so the
                // file is never left in ~/Desktop Bins with nothing showing it.
                do {
                    try self.release(removed, leaving: id)
                } catch {
                    NSLog("DesktopBinsWidget: could not return \(removed.displayName) to the Desktop: \(error)")
                    self.presentMoveFailure("Couldn't put “\(removed.displayName)” back on the Desktop",
                                            names: [error.localizedDescription, "", "It is still in the bin."])
                    return
                }
                bin.items.remove(at: index)
                self.commit(bin)
            }
            menu.addItem(.separator())
        }

        menu.addItem(withActionTitle: bin.isCollapsed ? "Expand Bin" : "Collapse Bin") { [weak self] in
            guard let self, let view = self.view(for: id) else { return }
            self.panelRequestsToggleCollapse(view)
        }
        let countItem = menu.addItem(withActionTitle: "Show Item Count") { [weak self] in
            guard let self, var bin = self.store.bin(for: id) else { return }
            bin.showsItemCount.toggle()
            self.commit(bin)
        }
        countItem.state = bin.showsItemCount ? .on : .off
        menu.addItem(withActionTitle: "Rename Bin…") { [weak self] in self?.renameBin(id) }
        menu.addItem(withActionTitle: "Change Color…") { [weak self] in self?.changeColor(id) }
        menu.addItem(.separator())
        menu.addItem(withActionTitle: "Delete Bin") { [weak self] in self?.deleteBin(id) }
        return menu
    }

    private func renameBin(_ id: UUID) {
        guard var bin = store.bin(for: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Bin"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = bin.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        bin.title = trimmed.isEmpty ? bin.title : trimmed
        commit(bin)
    }

    private var colorTargetID: UUID?

    private func changeColor(_ id: UUID) {
        guard let bin = store.bin(for: id) else { return }
        colorTargetID = id
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = NSColor(hex: bin.colorHex)
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let id = colorTargetID, var bin = store.bin(for: id) else { return }
        bin.colorHex = sender.color.hexString
        commit(bin)
    }

    private func deleteBin(_ id: UUID) {
        guard let bin = store.bin(for: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(bin.title)”?"
        alert.informativeText = bin.items.isEmpty
            ? "This removes the bin."
            : "This removes the bin. Files it moved off the Desktop are put back there; nothing is deleted."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            // Deleting a bin must not leave its files in ~/Desktop Bins with
            // nothing showing them. Anything that can't go back keeps the bin
            // alive, holding just those items.
            guard var doomed = store.bin(for: id) else { return }
            var stranded: [BinItem] = []
            for item in doomed.items {
                do {
                    try release(item, leaving: id)
                } catch {
                    NSLog("DesktopBinsWidget: could not return \(item.displayName) to the Desktop: \(error)")
                    stranded.append(item)
                }
            }
            if stranded.isEmpty {
                store.removeBin(id: id)
            } else {
                doomed.items = stranded
                commit(doomed)
                presentMoveFailure("Couldn't put everything back on the Desktop",
                                   names: stranded.map(\.displayName) + ["", "The bin was kept, holding just these."])
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Lets menu construction read linearly instead of via target/action selectors.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func invoke() { handler() }
}

private extension NSMenu {
    @discardableResult
    func addItem(withActionTitle title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        addItem(item)
        return item
    }
}
