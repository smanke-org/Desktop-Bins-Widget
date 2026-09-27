import AppKit

/// A display as the placement rules see it. Pulled out of `NSScreen` so the
/// rules can be exercised against any monitor arrangement, not just the one
/// attached right now.
struct DisplaySnapshot {
    let uuid: String
    let frame: NSRect
    let visibleFrame: NSRect

    static func current() -> [DisplaySnapshot] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = DisplayIdentity.uuid(for: screen) else { return nil }
            return DisplaySnapshot(uuid: uuid, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    /// Key for "this exact set of monitors", order-independent.
    static func signature(of displays: [DisplaySnapshot]) -> String {
        let ids = displays.map(\.uuid).sorted()
        return ids.isEmpty ? "none" : ids.joined(separator: "+")
    }
}

/// Decides where a bin belongs. Pure: it reads a bin and a list of displays
/// and never changes either, so nothing here can persist a position the user
/// didn't choose.
enum BinPlacementResolver {
    static func frame(for bin: Bin, displays: [DisplaySnapshot]) -> NSRect {
        func display(_ uuid: String) -> DisplaySnapshot? { displays.first { $0.uuid == uuid } }

        // 1. The arrangement the user made under exactly this set of monitors.
        if let placement = bin.layouts[DisplaySnapshot.signature(of: displays)],
           let target = display(placement.displayUUID) {
            return NSRect(
                x: target.frame.minX + CGFloat(placement.relativeX),
                y: target.frame.minY + CGFloat(placement.relativeY),
                width: placement.width,
                height: placement.height
            )
        }

        // 2. Where the user last put it on its own display. This is what keeps
        //    a bin still while other monitors come and go around it — waking
        //    from sleep reconnects displays one at a time.
        if let uuid = bin.displayUUID, let home = display(uuid) {
            return NSRect(
                x: home.frame.minX + CGFloat(bin.relativeX ?? 0),
                y: home.frame.minY + CGFloat(bin.relativeY ?? 0),
                width: bin.width,
                height: bin.height
            )
        }

        // 3. Its display is absent: show it on the main display rather than
        //    lose it, fitted to that screen. Shown only — never saved, so the
        //    bin returns home when its display comes back.
        let stored = NSRect(x: bin.x, y: bin.y, width: bin.width, height: bin.height)
        guard bin.displayUUID != nil,
              let main = displays.first(where: { $0.frame.origin == .zero }) ?? displays.first else {
            return stored
        }
        let relative = NSRect(
            x: main.frame.minX + CGFloat(bin.relativeX ?? 0),
            y: main.frame.minY + CGFloat(bin.relativeY ?? 0),
            width: bin.width,
            height: bin.height
        )
        return clamp(relative, into: main.visibleFrame)
    }

    static func clamp(_ frame: NSRect, into bounds: NSRect) -> NSRect {
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let x = min(max(frame.origin.x, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.origin.y, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Layouts saved automatically while displays reconnected after sleep.
    ///
    /// Before 1.1.15 a layout was recorded for every monitor set the app saw,
    /// including the partial sets a wake passes through, using wherever the bin
    /// happened to be at that instant. Those can be recognized: they contain the
    /// bin's own display but are a strict subset of another recorded set that
    /// also contains it. A set of monitors the user genuinely works at (two
    /// desks sharing a main display, say) is never a subset of another, so it
    /// is kept.
    static func wakeTransientSignatures(in bin: Bin) -> [String] {
        guard let home = bin.displayUUID else { return [] }
        func members(_ signature: String) -> Set<Substring> { Set(signature.split(separator: "+")) }
        let withHome = bin.layouts.keys.filter { members($0).contains(Substring(home)) }
        return withHome.filter { signature in
            let set = members(signature)
            return withHome.contains { other in other != signature && set.isStrictSubset(of: members(other)) }
        }.sorted()
    }
}
