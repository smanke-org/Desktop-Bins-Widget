import AppKit
import SwiftUI

/// Hosts the settings UI. The app is an accessory (menu bar only) app, so it
/// activates itself explicitly for the window to come to the front.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Sized here, not by SwiftUI: open at the content's natural height but never taller
        // than the screen (a MacBook Air can't fit it all), and scroll whatever is cut off.
        // Letting SwiftUI size a window that AppKit then clamps loops until AppKit aborts.
        let view = SettingsView(settings: SettingsStore.shared)
        let natural = NSHostingView(rootView: view).fittingSize
        let screen = NSScreen.main?.visibleFrame.size ?? natural
        let size = NSSize(width: natural.width, height: min(natural.height, max(screen.height - 80, 240)))
        let hosting = NSHostingController(rootView: ScrollView(.vertical) { view }.frame(maxHeight: .infinity))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Desktop Bins Widget Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: size.width, height: 200)
        window.contentMaxSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
