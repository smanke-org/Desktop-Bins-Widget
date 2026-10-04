import AppKit

/// User-tunable appearance and behaviour, persisted in UserDefaults.
///
/// The knobs differ from Desktop Bins: because a panel lays out its own
/// items rather than nudging Finder icons onto a grid, there is no snapping
/// to tune. Icon size and labels drive the layout instead.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let iconSize = "iconSize"
        static let showLabels = "showLabels"
        static let panelOpacity = "panelOpacity"
        static let moveDesktopFiles = "moveDesktopFiles"
        /// Pre-1.1.8 setting, read once so the choice carries over.
        static let legacyHideDesktopIcons = "hideDesktopIcons"
        static let requiresCommandToMove = "requiresCommandToMove"
        static let checkForUpdatesAtLaunch = "checkForUpdatesAtLaunch"
        static let skippedUpdateVersion = "skippedUpdateVersion"
    }

    static let defaultIconSize: Double = 48
    static let defaultOpacity: Double = 0.9

    var onChange: (() -> Void)?

    /// Backed by the system login-item registration rather than UserDefaults,
    /// since macOS is the source of truth and the user can change it in
    /// System Settings behind our back.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLoginController.isEnabled else { return }
            if !LaunchAtLoginController.setEnabled(launchAtLogin) {
                launchAtLogin = LaunchAtLoginController.isEnabled
            }
        }
    }

    @Published var iconSize: Double { didSet { save(); onChange?() } }
    @Published var showLabels: Bool { didSet { save(); onChange?() } }
    @Published var panelOpacity: Double { didSet { save(); onChange?() } }

    /// Move a Desktop file into `~/Desktop Bins` when it is put in a bin, so
    /// the same file isn't shown twice and a bin's contents stay local to
    /// this Mac. Affects items dropped from now on; files already moved stay
    /// put until they leave their bin.
    @Published var moveDesktopFiles: Bool { didSet { save() } }

    /// Shown to the user as "Click Title Bar to Move". Checked means a plain
    /// drag will *not* move a panel — Command-drag is required — which is
    /// what stops bins being nudged by accident. The stored name says what
    /// the flag actually does, since the label reads the other way round.
    @Published var requiresCommandToMove: Bool { didSet { save() } }

    /// Look for a newer release shortly after launch. Silent unless there is
    /// something to install, so it can't turn into a dialog on every launch.
    @Published var checkForUpdatesAtLaunch: Bool { didSet { save() } }

    /// A Dock icon whose right-click menu opens Settings. Off by default.
    @Published var showInDock: Bool = AppPresence.showInDock {
        didSet {
            guard showInDock != AppPresence.showInDock else { return }
            AppPresence.showInDock = showInDock
            // Settings is the key window while its own toggle is clicked.
            AppPresence.applyDock(keepInFront: NSApp.keyWindow)
        }
    }

    /// The menu bar icon. On by default; may be off together with the Dock icon.
    @Published var showInMenuBar: Bool = AppPresence.showInMenuBar {
        didSet {
            guard showInMenuBar != AppPresence.showInMenuBar else { return }
            AppPresence.showInMenuBar = showInMenuBar
        }
    }

    /// A version the user chose to skip. The launch check stays quiet about
    /// it; asking again on every launch would just be nagging. Checking
    /// manually still offers it.
    var skippedUpdateVersion: String? {
        get { UserDefaults.standard.string(forKey: Key.skippedUpdateVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Key.skippedUpdateVersion) }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.iconSize: Self.defaultIconSize,
            Key.showLabels: true,
            Key.panelOpacity: Self.defaultOpacity,
            Key.moveDesktopFiles: defaults.object(forKey: Key.legacyHideDesktopIcons) as? Bool ?? true,
            Key.requiresCommandToMove: true,
            Key.checkForUpdatesAtLaunch: true
        ])
        launchAtLogin = LaunchAtLoginController.isEnabled
        iconSize = defaults.double(forKey: Key.iconSize)
        showLabels = defaults.bool(forKey: Key.showLabels)
        panelOpacity = defaults.double(forKey: Key.panelOpacity)
        moveDesktopFiles = defaults.bool(forKey: Key.moveDesktopFiles)
        requiresCommandToMove = defaults.bool(forKey: Key.requiresCommandToMove)
        checkForUpdatesAtLaunch = defaults.bool(forKey: Key.checkForUpdatesAtLaunch)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(iconSize, forKey: Key.iconSize)
        defaults.set(showLabels, forKey: Key.showLabels)
        defaults.set(panelOpacity, forKey: Key.panelOpacity)
        defaults.set(moveDesktopFiles, forKey: Key.moveDesktopFiles)
        defaults.set(requiresCommandToMove, forKey: Key.requiresCommandToMove)
        defaults.set(checkForUpdatesAtLaunch, forKey: Key.checkForUpdatesAtLaunch)
    }

    /// Smallest a panel can be: one column of icons plus its insets, so a
    /// narrow single-column panel is possible at any icon size.
    var minPanelWidth: Double { cellWidth + 2 * Double(WidgetMetrics.contentInset) }
    var minPanelHeight: Double {
        Double(WidgetMetrics.titleBarHeight) + cellHeight + 2 * Double(WidgetMetrics.contentInset)
    }

    /// Cell size derived from the icon size, leaving room for the label.
    var cellWidth: Double { iconSize + 36 }
    var cellHeight: Double { iconSize + (showLabels ? Double(WidgetMetrics.labelHeight) : 8) + 12 }

    func resetToDefaults() {
        iconSize = Self.defaultIconSize
        showLabels = true
        panelOpacity = Self.defaultOpacity
        moveDesktopFiles = true
        requiresCommandToMove = true
        checkForUpdatesAtLaunch = true
    }
}
