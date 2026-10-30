import AppKit
import SwiftUI

// MARK: - Content

/// One page of Help. `Help.resolve` swaps `{…}` tokens for the user's own settings, such
/// as their shortcuts, so the text matches what they've set up.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum HelpBlock {
    case text(String)
    case heading(String)
    /// Keys on the left, what they do on the right.
    case keys([(String, String)])
    case tip(String)

    var searchText: String {
        switch self {
        case .text(let s), .heading(let s), .tip(let s): Help.resolve(s)
        case .keys(let rows): rows.map { Help.resolve($0.0) + " " + Help.resolve($0.1) }.joined(separator: " ")
        }
    }
}

@MainActor
enum Help {
    /// Desktop Bins Widget has no shortcuts the user sets, so nothing needs swapping.
    static func resolve(_ text: String) -> String { text }
    static var debugTokens: String { "" }
    static let testTabs = ["Settings"]
    static func topic(forSettingsTab tab: String) -> String { "getting-started" }

    static var topics: [HelpTopic] { [
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "sparkles", blocks: [
            .text("Desktop Bins Widget puts tidy panels, called bins, on your desktop. Drag files, folders and apps into a bin to keep shortcuts to them close at hand. Each bin belongs to the desktop it's on and remembers where it goes for each set of monitors."),
            .keys([
                ("New Bin (⌘N)", "Make a bin (menu bar menu)"),
                ("Hide All Bins / Show All Bins", "Put the bins away and bring them back"),
                ("Drag in", "Add files, folders or apps to a bin"),
                ("Drag within a bin", "Reorder its items"),
                ("Double-click an item", "Open it"),
            ]),
            .tip("Items flow in the order you arrange them, so a bin never has gaps."),
            .tip("While ToolHUD is running, Desktop Bins Widget's menu moves into ToolHUD's menu bar menu as a submenu, and the icon here steps aside until ToolHUD quits. To keep the icon, turn off \"Put in ToolHUD's menu while ToolHUD is running\" in Settings."),
            .tip("Quitting asks first, since your bins leave the desktop while Desktop Bins Widget is closed. Turn off \"Ask before quitting\" in Settings › General, or tick \"Don't ask again\" when it asks."),
        ]),

        HelpTopic(id: "bins", title: "Working with Bins", symbol: "square.grid.2x2", blocks: [
            .heading("Moving and resizing"),
            .text("Drag a bin's title bar to move it, and drag the grip in its bottom-right corner to resize it. With \"Click Title Bar to Move\" on in Settings, hold ⌘ while dragging the title bar, so bins aren't nudged by accident."),
            .heading("Right-click a bin"),
            .keys([
                ("Collapse / Expand Bin", "Fold it down to its title bar"),
                ("Show Item Count", "Show how many items it holds"),
                ("Rename Bin…", "Give it a name"),
                ("Change Color…", "Pick its color"),
                ("Delete Bin", "Remove the bin (the files themselves stay)"),
            ]),
            .heading("Right-click an item"),
            .keys([
                ("Open", "Open the file, folder or app"),
                ("Reveal in Finder", "Show where it is"),
                ("Remove from Bin", "Take the shortcut out of the bin"),
            ]),
        ]),

        HelpTopic(id: "desktop-files", title: "Desktop Files", symbol: "doc.on.doc", blocks: [
            .text("With \"Move Desktop files into bins\" on, a file you drag in from the Desktop moves to the Desktop Bins folder in your home folder, so it isn't shown twice. That folder doesn't sync, so your bins stay on this Mac and other computers just see the file gone from the Desktop."),
            .keys([
                ("Show Desktop Bins Folder", "Open that folder (Tools menu)"),
                ("Return All Files to Desktop…", "Put every moved file back on the Desktop"),
            ]),
        ]),

        HelpTopic(id: "view", title: "View and Tools", symbol: "slider.horizontal.3", blocks: [
            .text("The menu bar menu's View submenu sets the icon size and whether file names show under icons; Settings › Bins also sets the panels' opacity."),
            .keys([
                ("Bring All Bins to Main Display…", "Gather bins that ended up off screen"),
                ("Remove Missing Items", "Clear out shortcuts to files that no longer exist"),
            ]),
        ]),

        HelpTopic(id: "automation", title: "Automation", symbol: "gearshape.2", blocks: [
            .keys([
                ("desktopbins://new-bin", "Make a new bin"),
                ("desktopbins://toggle", "Show or hide every bin"),
                ("desktopbins://folder", "Open the Desktop Bins folder"),
            ]),
            .text("Use these links from Shortcuts, scripts or a launcher. ToolHUD's Desktop Bins Widget buttons use them."),
        ]),

        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("A bin disappeared"),
            .text("It may be on a display that's no longer connected, or hidden. Choose Show All Bins, or Bring All Bins to Main Display… in the Tools menu."),
            .heading("An item shows as missing"),
            .text("The file it points to was deleted or moved somewhere it can't be found. Remove Missing Items clears these out."),
            .heading("A bin won't move"),
            .text("If \"Click Title Bar to Move\" is on, hold ⌘ while you drag the title bar."),
        ]),
    ] }
}

// MARK: - Window

/// ObservableObject rather than @Observable, so this works on macOS 13.
@MainActor
final class HelpState: ObservableObject {
    @Published var selection: String? = "getting-started"
    @Published var query = ""
}

@MainActor
final class HelpWindow: NSObject, NSWindowDelegate {
    static let shared = HelpWindow()

    let state = HelpState()
    private(set) var window: NSWindow?

    /// Opens Help, on `topic` when given.
    func show(topic: String? = nil) {
        if let topic { state.query = ""; state.selection = topic }
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(state: state))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Desktop Bins Widget Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let screen = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 820, height: min(600, screen - 80)))
            window.contentMinSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("DesktopBinsWidgetHelp")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @ObservedObject var state: HelpState

    private var matches: [HelpTopic] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Help.topics }
        return Help.topics.filter { topic in
            topic.title.lowercased().contains(query) || topic.blocks.contains { $0.searchText.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $state.selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .overlay {
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        } detail: {
            if let topic = Help.topics.first(where: { $0.id == state.selection }) {
                HelpPage(topic: topic, query: state.query)
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: state.query) { _ in
            // Keep a matching topic on screen while searching.
            if let first = matches.first, !matches.contains(where: { $0.id == state.selection }) { state.selection = first.id }
        }
    }
}

struct HelpPage: View {
    let topic: HelpTopic
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .text(let s):
            Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(Help.resolve(s)).font(.title3.weight(.semibold)).padding(.top, 8)
        case .tip(let s):
            Label { Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .keys(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let keys = Help.resolve(row.0), what = Help.resolve(row.1)
                    let hit = !query.isEmpty && (keys + " " + what).lowercased().contains(query.lowercased())
                    GridRow {
                        Text(keys)
                            .font(.body.monospaced().weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            // The same key column width in every table on every page.
                            .frame(width: 210, alignment: .leading)
                        Text(what).fixedSize(horizontal: false, vertical: true)
                    }
                    .background(hit ? Color.yellow.opacity(0.25) : .clear)
                }
            }
        }
    }
}

/// The round "?" button macOS puts in the corner of settings panes.
struct HelpButton: NSViewRepresentable {
    let topic: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open))
        button.bezelStyle = .helpButton
        button.toolTip = "Desktop Bins Widget Help"
        button.setAccessibilityLabel("Help")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.topic = topic }

    func makeCoordinator() -> Coordinator { Coordinator(topic: topic) }

    @MainActor
    final class Coordinator: NSObject {
        var topic: String
        init(topic: String) { self.topic = topic }
        @objc func open() { HelpWindow.shared.show(topic: topic) }
    }
}
