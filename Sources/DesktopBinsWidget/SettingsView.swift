import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("General") {
                Toggle("Open Desktop Bins Widget at login", isOn: $settings.launchAtLogin)
                Toggle("Check for updates when the app opens", isOn: $settings.checkForUpdatesAtLaunch)
                    .help("Looks for a newer release on GitHub a few seconds after launch. You are only asked if there is one.")
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .help("Adds a Dock icon whose right-click menu opens Settings. Desktop Bins Widget stays in the menu bar either way.")
            }

            Divider()

            section("Appearance") {
                slider(label: "Icon size", value: $settings.iconSize, range: 24...96, step: 8, suffix: "pt")
                slider(label: "Panel opacity", value: $settings.panelOpacity, range: 0.3...1.0, step: 0.05, suffix: "")
                Toggle("Show file names under icons", isOn: $settings.showLabels)
            }

            Divider()

            section("Behavior") {
                Toggle("Click Title Bar to Move", isOn: $settings.requiresCommandToMove)
                    .help("On: hold ⌘ and drag the title bar to move a bin. Off: drag the title bar directly.")
                caption(settings.requiresCommandToMove
                        ? "Hold ⌘ and drag the title bar to move a bin. Stops bins being nudged by accident."
                        : "Drag the title bar directly to move a bin.")

                Toggle("Move Desktop files into bins", isOn: $settings.moveDesktopFiles)
                    .padding(.top, 4)
                caption("A file you drag in from the Desktop moves to the Desktop Bins folder in your home folder, so it isn't shown twice. That folder doesn't sync, so your bins stay on this Mac and other computers just see the file leave their Desktop. Removing it from its bin puts it back on the Desktop. Items from anywhere else are never moved.")

                caption("Items flow in the order you arrange them, so panels never leave gaps. Drag an item within a bin to reorder it.")
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                Spacer()
                Text("Desktop Bins Widget \(AppInfo.displayVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(suffix.isEmpty
                     ? String(format: "%.0f%%", value.wrappedValue * 100)
                     : "\(Int(value.wrappedValue)) \(suffix)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
