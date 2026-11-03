import AppKit

/// The running app's bin store and panel controller, set once at launch.
enum AgentApp {
    static var store: BinStore?
    static var panels: BinPanelController?
}

/// Everything an agent can do in Desktop Bins Widget. Add a command here and the CLI, `help`,
/// and the MCP tools all get it. Each `run` is on the main actor and calls the same code as the
/// bins' right-click menus, drag and drop, the menu bar menu and the desktopbins:// links, so
/// the panels on the desktop update live.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the version, how many bins and items there are (`missingItems`: items whose file is gone), whether the bins are on the desktop (`panelsVisible`), whether Desktop files move into the Desktop Bins folder (`moveDesktopFiles`), and that folder's path.",
                     example: "bins status --json", readOnly: true) { _ in
            let (store, panels) = try app()
            let items = store.bins.flatMap(\.items)
            return ["app": AppInfo.name, "version": AppInfo.version,
                    "bins": store.bins.count, "items": items.count, "missingItems": items.filter(\.isMissing).count,
                    "panelsVisible": panels.isVisible, "moveDesktopFiles": SettingsStore.shared.moveDesktopFiles,
                    "binFolder": LocalBinFolder.url.path, "testCopy": AgentSocket.isTestRun]
        },

        // MARK: Bins

        AgentCommand(name: "list", summary: "List the bins in the order they were made. Returns `bins` (id, name, items, color, collapsed, showsItemCount, and x, y, width, height of the panel on screen in points, origin at the bottom left of the main display), `total` and `nextOffset` when there are more.",
                     params: [limitParam, offsetParam],
                     example: "bins list --json", readOnly: true) { args in
            let (store, _) = try app()
            return try page(store.bins, args, key: "bins") { summary($0) }
        },
        AgentCommand(name: "show", summary: "Show one bin and what it holds, in order. Each item has its id, name, path, its position in the bin (`index`, from 0), whether its file is missing, and whether the bin moved it off the Desktop (`movedFromDesktop`: it goes back there when it leaves the bin).",
                     params: [binParam],
                     example: "bins show Work --json", readOnly: true) { args in
            let bin = try findBin(args.required("bin"))
            var result = summary(bin)
            result["items"] = bin.items.enumerated().map { itemSummary($0.element, index: $0.offset) }
            return result
        },
        AgentCommand(name: "create", summary: "Make a new bin in the middle of the main display, as New Bin in the menu bar menu does.",
                     params: [.init(name: "name", help: "its name (default \"New Bin\")"),
                              .init(name: "color", help: "its color as a hex code, like 10B981 (default: the next color in turn)")],
                     example: "bins create --name Work --color 10B981 --json") { args in
            let (_, panels) = try app()
            let color = try args.string("color").map(hexColor)
            if let name = args.string("name"), name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentError.invalid("--name can't be empty")
            }
            let id = panels.addBinAtCenterOfMainScreen()
            if let name = args.string("name") { panels.renameBin(id, to: name) }
            if let color { panels.setColor(color, forBin: id) }
            return summary(try findBin(id))
        },
        AgentCommand(name: "update", summary: "Change a bin's name, color, item count in its title, or collapse it to its title bar, as its right-click menu does. Only the options you give change.",
                     params: [binParam,
                              .init(name: "name", help: "a new name"),
                              .init(name: "color", help: "a new color as a hex code, like F59E0B"),
                              .init(name: "show-count", kind: .boolean, help: "true or false: show \"(n)\" after the name"),
                              .init(name: "collapsed", kind: .boolean, help: "true folds the bin to its title bar, false opens it again")],
                     example: "bins update Work --name Projects --collapsed false --json") { args in
            let (_, panels) = try app()
            let before = try findBin(args.required("bin"))
            let id = before.id
            let color = try args.string("color").map(hexColor)
            if let name = args.string("name") {
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentError.invalid("--name can't be empty") }
                panels.renameBin(id, to: name)
            }
            if let color, color != before.colorHex { panels.setColor(color, forBin: id) }
            if let shows = try args.bool("show-count"), shows != before.showsItemCount { panels.setShowsItemCount(shows, forBin: id) }
            if let collapsed = try args.bool("collapsed"), collapsed != before.isCollapsed { panels.toggleCollapse(id) }
            let after = try findBin(id)
            var result = summary(after)
            result["changed"] = after != before
            return result
        },
        AgentCommand(name: "delete", summary: "Delete a bin, as Delete Bin does. Files it moved off the Desktop go back there; no file is deleted. Without --yes it only shows what it would do.",
                     params: [binParam],
                     example: "bins delete Work --yes --json", destructive: true) { args in
            let (_, panels) = try app()
            let bin = try findBin(args.required("bin"))
            let returning = bin.items.filter { $0.desktopName != nil }.map(\.displayName)
            guard args.confirmed else {
                return ["wouldDelete": summary(bin), "filesBackToDesktop": returning,
                        "hint": "add --yes (over MCP, set yes to true) to delete the bin. Its \(bin.items.count) item(s) leave with it; files it moved off the Desktop go back there"]
            }
            let stranded = panels.deleteBinReturningFiles(bin.id)
            if stranded.isEmpty { return ["deleted": short(bin.id), "name": bin.title, "filesBackToDesktop": returning] }
            throw AgentError.invalid("couldn't put \(stranded.map(\.displayName).joined(separator: ", ")) back on the Desktop, so the bin was kept, holding just those")
        },

        // MARK: Panels

        AgentCommand(name: "panels show", summary: "Put every bin back on the desktop, as Show All Bins does.",
                     example: "bins panels show --json") { _ in
            try setPanelsVisible(true)
        },
        AgentCommand(name: "panels hide", summary: "Take every bin off the desktop until they're shown again, as Hide All Bins does. The bins and their items stay.",
                     example: "bins panels hide --json") { _ in
            try setPanelsVisible(false)
        },
        AgentCommand(name: "panels gather", summary: "Bring every bin onto the main display and pin it there, as Bring All Bins to Main Display does: for bins stranded on a monitor that's gone. Their places on other displays are replaced. Without --yes it only shows what it would move.",
                     example: "bins panels gather --yes --json", destructive: true) { args in
            let (store, panels) = try app()
            guard args.confirmed else {
                return ["wouldMove": store.bins.map { summary($0) },
                        "hint": "add --yes (over MCP, set yes to true) to move these bins onto the main display"]
            }
            let moved = panels.consolidateBinsToMainDisplay()
            return ["moved": moved, "bins": store.bins.map { summary($0) }]
        },

        // MARK: Items

        AgentCommand(name: "items list", summary: "List the items in every bin, or in one, in bin order. Returns `items` (id, name, path, bin, binId, index, missing, movedFromDesktop), `total` and `nextOffset` when there are more.",
                     params: [.init(name: "bin", help: "only this bin (its id or name)"),
                              .init(name: "search", help: "only items whose name or path contains this"),
                              .init(name: "missing", kind: .boolean, help: "only items whose file is gone"),
                              limitParam, offsetParam],
                     example: "bins items list --search report --json", readOnly: true) { args in
            let (store, _) = try app()
            let bins = try args.string("bin").map { [try findBin($0)] } ?? store.bins
            let search = args.string("search")?.lowercased()
            let missing = try args.bool("missing") == true
            let rows: [JSONObject] = bins.flatMap { bin in
                bin.items.enumerated().compactMap { index, item -> JSONObject? in
                    if missing, !item.isMissing { return nil }
                    if let search, !item.displayName.lowercased().contains(search), !item.path.lowercased().contains(search) { return nil }
                    var row = itemSummary(item, index: index)
                    row["bin"] = bin.title
                    row["binId"] = short(bin.id)
                    return row
                }
            }
            return try page(rows, args, key: "items") { $0 }
        },
        AgentCommand(name: "items add", summary: "Put a file or folder in a bin, as dropping it on the bin does. A file straight on the Desktop moves into the Desktop Bins folder while \"Move Desktop files into bins\" is on in Settings (it goes back when it leaves the bin); anything else stays where it is and the bin points at it. A file already in the bin is skipped.",
                     params: [.init(name: "path", kind: .path, required: true, positional: true, help: "the file or folder"),
                              .init(name: "bin", required: true, help: "the bin (its id or name)"),
                              .init(name: "index", kind: .integer, help: "where in the bin, from 0 (default: at the end)")],
                     example: "bins items add ~/Documents/report.pdf --bin Work --json") { args in
            let (_, panels) = try app()
            let bin = try findBin(args.required("bin"))
            let path = try absolutePath(args.required("path"))
            guard FileManager.default.fileExists(atPath: path) else { throw AgentError.notFound("nothing at \(path)") }
            let url = URL(fileURLWithPath: path)
            let index = try args.int("index", default: bin.items.count)
            let result = panels.addItems([url], toBin: bin.id, at: index)
            guard let item = result.added.first else {
                return ["added": false, "hint": "it's already in \(bin.title)", "bin": summary(try findBin(bin.id))]
            }
            let after = try findBin(bin.id)
            var row = itemSummary(item, index: after.items.firstIndex { $0.id == item.id } ?? index)
            row["added"] = true
            if !result.failed.isEmpty { row["warning"] = "couldn't move it off the Desktop, so it was added where it is" }
            return row
        },
        AgentCommand(name: "items remove", summary: "Take an item out of its bin, as Remove from Bin does. No file is deleted: a file the bin moved off the Desktop goes back there, anything else stays where it is. Without --yes it only shows what it would do.",
                     params: [itemParam, itemBinParam],
                     example: "bins items remove 3f2a9c1e --yes --json", destructive: true) { args in
            let (_, panels) = try app()
            let (bin, index) = try findItem(args.required("item"), bin: args.string("bin"))
            let item = bin.items[index]
            guard args.confirmed else {
                return ["wouldRemove": itemSummary(item, index: index), "bin": bin.title,
                        "hint": "add --yes (over MCP, set yes to true) to remove it from the bin. "
                            + (item.desktopName != nil ? "Its file goes back to the Desktop" : "Its file stays where it is")]
            }
            do {
                try panels.removeItem(at: index, fromBin: bin.id)
            } catch {
                throw AgentError.invalid("couldn't put \(item.displayName) back on the Desktop (\(error.localizedDescription)), so it is still in the bin")
            }
            return ["removed": short(item.id), "name": item.displayName, "bin": bin.title,
                    "backOnDesktop": item.desktopName != nil]
        },
        AgentCommand(name: "items move", summary: "Move an item to another place in its bin, as dragging it there does.",
                     params: [itemParam, itemBinParam,
                              .init(name: "index", kind: .integer, required: true, help: "its new place, from 0 (0 is first)")],
                     example: "bins items move 3f2a9c1e --index 0 --json") { args in
            let (_, panels) = try app()
            let (bin, index) = try findItem(args.required("item"), bin: args.string("bin"))
            let target = try args.int("index", default: index)
            guard target >= 0 else { throw AgentError.usage("--index must be 0 or more") }
            let id = bin.items[index].id
            panels.moveItem(inBin: bin.id, from: index, to: target)
            let after = try findBin(bin.id)
            let now = after.items.firstIndex { $0.id == id } ?? index
            return ["id": short(id), "name": after.items[now].displayName, "index": now, "changed": now != index]
        },
        AgentCommand(name: "items open", summary: "Open an item in its app, as double-clicking it does (an alias opens what it points at).",
                     params: [itemParam, itemBinParam],
                     example: "bins items open 3f2a9c1e --json") { args in
            let (_, panels) = try app()
            let (bin, index) = try findItem(args.required("item"), bin: args.string("bin"))
            let item = bin.items[index]
            guard panels.openItem(at: index, inBin: bin.id) else {
                throw AgentError.notFound("\(item.displayName) can't be found: its file was deleted or moved somewhere the bin can't follow. `bins items remove-missing` clears such items")
            }
            return ["opened": short(item.id), "name": item.displayName, "path": item.resolvedTargetURL()?.path ?? item.path]
        },
        AgentCommand(name: "items remove-missing", summary: "Take every item whose file no longer exists out of its bin, as Remove Missing Items does. Without --yes it only lists them.",
                     example: "bins items remove-missing --yes --json", destructive: true) { args in
            let (store, panels) = try app()
            let missing: [JSONObject] = store.bins.flatMap { bin in
                bin.items.enumerated().filter { $0.element.isMissing }.map { index, item in
                    var row = itemSummary(item, index: index)
                    row["bin"] = bin.title
                    return row
                }
            }
            guard args.confirmed else {
                return ["wouldRemove": missing,
                        "hint": missing.isEmpty ? "every item still points at a file that exists" : "add --yes (over MCP, set yes to true) to remove these"]
            }
            return ["removed": panels.removeMissingItems(), "items": missing]
        },
        AgentCommand(name: "files return", summary: "Put every file the bins moved off the Desktop back on the Desktop, as Return All Files to Desktop does. The items stay in their bins, pointing at the Desktop copy. Without --yes it only lists them.",
                     example: "bins files return --yes --json", destructive: true) { args in
            let (store, panels) = try app()
            let moved: [JSONObject] = store.bins.flatMap { bin in
                bin.items.enumerated().filter { $0.element.desktopName != nil }.map { index, item in
                    var row = itemSummary(item, index: index)
                    row["bin"] = bin.title
                    return row
                }
            }
            guard args.confirmed else {
                return ["wouldReturn": moved,
                        "hint": moved.isEmpty ? "no bin holds a file moved from the Desktop" : "add --yes (over MCP, set yes to true) to put these back on the Desktop"]
            }
            let result = panels.returnAllFilesToDesktop()
            return ["returned": result.returned, "failed": result.failed]
        },
    ]

    // MARK: Params

    static let binParam = AgentCommand.Param(name: "bin", required: true, positional: true,
                                             help: "the bin: its id (the first 8 characters are enough) or its name")
    static let itemParam = AgentCommand.Param(name: "item", required: true, positional: true,
                                              help: "the item: its id (the first 8 characters are enough), or its name together with --bin")
    static let itemBinParam = AgentCommand.Param(name: "bin", help: "the bin it's in (its id or name), when the item is given by name")
    static let limitParam = AgentCommand.Param(name: "limit", kind: .integer, help: "at most this many (default 50)")
    static let offsetParam = AgentCommand.Param(name: "offset", kind: .integer, help: "skip this many, for the next page")

    // MARK: Helpers

    private static func app() throws -> (BinStore, BinPanelController) {
        guard let store = AgentApp.store, let panels = AgentApp.panels else {
            throw AgentError.unavailable("Desktop Bins Widget is still starting. Try again in a moment")
        }
        return (store, panels)
    }

    static func short(_ id: UUID) -> String { String(id.uuidString.lowercased().prefix(8)) }

    private static func findBin(_ id: UUID) throws -> Bin {
        guard let bin = AgentApp.store?.bin(for: id) else { throw AgentError.notFound("the bin went away while it was changing") }
        return bin
    }

    /// A bin by any unique start of its id, or by its name (any case).
    static func findBin(_ ref: String) throws -> Bin {
        let (store, _) = try app()
        let key = ref.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { throw AgentError.usage("give a bin id or name. Run `bins list`") }
        var matches = store.bins.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        if matches.isEmpty { matches = store.bins.filter { $0.title.lowercased() == key } }
        guard !matches.isEmpty else { throw AgentError.notFound("no bin with id or name \"\(ref)\". Run `bins list`") }
        guard matches.count == 1 else {
            throw AgentError.invalid("\"\(ref)\" matches \(matches.count) bins (\(matches.map { "\(short($0.id)) \($0.title)" }.joined(separator: ", "))). Use the id")
        }
        return matches[0]
    }

    /// An item by any unique start of its id, or by its name (any case), in one bin or all.
    static func findItem(_ ref: String, bin binRef: String?) throws -> (Bin, Int) {
        let (store, _) = try app()
        let bins = try binRef.map { [try findBin($0)] } ?? store.bins
        let key = ref.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { throw AgentError.usage("give an item id or name. Run `bins items list`") }
        func matching(_ test: (BinItem) -> Bool) -> [(Bin, Int)] {
            bins.flatMap { bin in bin.items.indices.filter { test(bin.items[$0]) }.map { (bin, $0) } }
        }
        var matches = matching { $0.id.uuidString.lowercased().hasPrefix(key) }
        if matches.isEmpty {
            matches = matching { $0.displayName.lowercased() == key || URL(fileURLWithPath: $0.path).lastPathComponent.lowercased() == key }
        }
        guard !matches.isEmpty else {
            throw AgentError.notFound("no item with id or name \"\(ref)\"\(binRef.map { " in \($0)" } ?? ""). Run `bins items list`")
        }
        guard matches.count == 1 else {
            throw AgentError.invalid("\"\(ref)\" matches \(matches.count) items (\(matches.map { "\(short($0.0.items[$0.1].id)) in \($0.0.title)" }.joined(separator: ", "))). Use the id")
        }
        return matches[0]
    }

    /// "#10b981", "10B981" or "1b8" as the app stores colors: "10B981".
    private static func hexColor(_ raw: String) throws -> String {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard [3, 6].contains(hex.count), hex.allSatisfy(\.isHexDigit) else {
            throw AgentError.usage("--color must be a hex code like 10B981, not \"\(raw)\"")
        }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        return hex.uppercased()
    }

    /// The app side gets paths from MCP as they were typed: they must be absolute.
    private static func absolutePath(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw AgentError.usage("the path must be absolute, not \"\(path)\"") }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func setPanelsVisible(_ visible: Bool) throws -> JSONObject {
        let (store, panels) = try app()
        let changed = panels.isVisible != visible
        if changed { panels.setAllVisible(visible) }
        return ["panelsVisible": panels.isVisible, "bins": store.bins.count, "changed": changed]
    }

    static func summary(_ bin: Bin) -> JSONObject {
        let frame = AgentApp.panels?.frame(ofBin: bin.id) ?? NSRect(x: bin.x, y: bin.y, width: bin.width, height: bin.height)
        return ["id": short(bin.id), "name": bin.title, "items": bin.items.count, "color": bin.colorHex,
                "collapsed": bin.isCollapsed, "showsItemCount": bin.showsItemCount,
                "x": Int(frame.minX.rounded()), "y": Int(frame.minY.rounded()),
                "width": Int(frame.width.rounded()), "height": Int(frame.height.rounded())]
    }

    static func itemSummary(_ item: BinItem, index: Int) -> JSONObject {
        let url = item.resolveURL()
        return ["id": short(item.id), "name": item.displayName, "path": url?.path ?? item.path, "index": index,
                "missing": url == nil, "movedFromDesktop": item.desktopName != nil]
    }

    private static func page<T>(_ all: [T], _ args: Args, key: String, _ row: (T) -> JSONObject) throws -> JSONObject {
        let limit = try args.int("limit", default: 50), offset = try args.int("offset", default: 0)
        guard limit > 0, offset >= 0 else { throw AgentError.usage("--limit must be 1 or more and --offset 0 or more") }
        let slice = all.dropFirst(offset).prefix(limit)
        var result: JSONObject = [key: slice.map(row), "total": all.count]
        if offset + slice.count < all.count { result["nextOffset"] = offset + slice.count }
        return result
    }
}
