import Foundation

/// Loads and saves the panel layout as JSON under Application Support.
final class BinStore {
    private(set) var bins: [Bin] = []
    var onChange: (() -> Void)?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // An agent CLI test copy (Debug builds only) keeps its bins in the APP_STORE folder.
        let dir = AgentSocket.testFolder ?? appSupport.appendingPathComponent("DesktopBinsWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bins.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            bins = []
            return
        }
        bins = (try? JSONDecoder().decode([Bin].self, from: data)) ?? []
    }

    func save() {
        guard let data = try? JSONEncoder().encode(bins) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addBin(_ bin: Bin) {
        bins.append(bin)
        save()
        onChange?()
    }

    func removeBin(id: UUID) {
        bins.removeAll { $0.id == id }
        save()
        onChange?()
    }

    /// Updates a bin in place. Pass `notify: true` when the change affects
    /// which windows exist rather than just their contents.
    func updateBin(_ bin: Bin, notify: Bool = false) {
        guard let idx = bins.firstIndex(where: { $0.id == bin.id }) else { return }
        bins[idx] = bin
        save()
        if notify { onChange?() }
    }

    func bin(for id: UUID) -> Bin? {
        bins.first { $0.id == id }
    }
}
