import AppKit
import SwiftUI

/// Hosts the settings UI. The app is an accessory (menu bar only) app, so it
/// activates itself explicitly for the window to come to the front.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// The width Settings is laid out for, and the smallest the window can be dragged to.
    static let width: CGFloat = 430
    static let minimumSize = NSSize(width: width, height: 280)

    /// The content size the user last dragged the window to (per Mac, not synced), or nil
    /// while they haven't: then Settings opens at its own height.
    static var chosenSize: NSSize? {
        get { UserDefaults.standard.string(forKey: "settings.contentSize").map(NSSizeFromString) }
        set { UserDefaults.standard.set(newValue.map(NSStringFromSize), forKey: "settings.contentSize") }
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            WhatsNew.shared.present(on: window)
            return
        }

        // Sized here, not by SwiftUI: open at the content's natural height but never taller
        // than the screen (a MacBook Air can't fit it all), and scroll whatever is cut off.
        // Letting SwiftUI size a window that AppKit then clamps loops until AppKit aborts.
        // The content fills whatever size the user drags the window to.
        let view = SettingsView(settings: SettingsStore.shared)
        let hosting = NSHostingView(rootView: ScrollView(.vertical) { view }
            .frame(minWidth: Self.width, maxWidth: .infinity, maxHeight: .infinity))
        hosting.sizingOptions = []
        // In a plain container: a window whose content is the SwiftUI view itself resets the
        // minimum size to zero as soon as it's shown.
        let container = NSViewController()
        container.view = NSView(frame: NSRect(origin: .zero, size: Self.minimumSize))
        hosting.frame = container.view.bounds
        hosting.autoresizingMask = [.width, .height]
        container.view.addSubview(hosting)
        let window = NSWindow(contentViewController: container)
        window.title = "Desktop Bins Widget Settings"
        // Resizable as well as scrolling: drag it bigger to see more at once.
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = Self.minimumSize
        window.setContentSize(fittingSize(view))
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // After an update whose notes weren't seen yet.
        WhatsNew.shared.present(on: window)
    }

    /// This version's release notes, when asked for from Settings.
    func showWhatsNew() {
        if let window { WhatsNew.shared.present(on: window, asked: true) }
    }

    /// The natural height measured at the fixed width, no taller than the screen; once the
    /// user has dragged the window to a size, that size instead (still capped to the screen).
    private func fittingSize(_ view: SettingsView) -> NSSize {
        let available = max((NSScreen.main?.visibleFrame.height ?? 800) - 80, Self.minimumSize.height)
        if let chosen = Self.chosenSize {
            return NSSize(width: max(chosen.width, Self.minimumSize.width),
                          height: min(max(chosen.height, Self.minimumSize.height), available))
        }
        let natural = NSHostingView(rootView: view.frame(width: Self.width)).fittingSize
        return NSSize(width: Self.width, height: min(max(natural.height, Self.minimumSize.height), available))
    }

    /// A size the user dragged to is kept, and used next time.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window else { return }
        Self.chosenSize = window.contentRect(forFrameRect: window.frame).size
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    #if DEBUG
    var debugWindow: NSWindow? { window }
    #endif
}
