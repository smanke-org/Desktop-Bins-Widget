import Foundation

/// `~/Desktop Bins`: where files put into a bin from the Desktop are kept.
///
/// The Desktop is often synced — here by OneDrive — and anything done to a
/// file there is copied to every other computer. Hiding it left invisible
/// files on machines that have no bins to show them in. Moving it into a
/// folder that is not synced keeps a bin's contents local to this Mac: other
/// computers see the file leave their Desktop, and nothing more.
enum LocalBinFolder {
    static var url: URL {
        // An agent CLI test copy (Debug builds only) never touches the real folder.
        if let test = AgentSocket.testFolder { return test.appendingPathComponent("Desktop Bins", isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop Bins", isDirectory: true)
    }

    static var desktop: URL? {
        // A test copy gets a stand-in Desktop inside its APP_STORE folder, so files it puts
        // back "on the Desktop" never land on the real one.
        if let test = AgentSocket.testFolder {
            let desktop = test.appendingPathComponent("Desktop", isDirectory: true)
            try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
            return desktop
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    /// True for items sitting directly on the Desktop. Items from anywhere
    /// else are only referenced: moving something out of a folder the user
    /// is actively browsing is not what dropping it on a bin asks for.
    static func isOnDesktop(_ url: URL) -> Bool {
        guard let desktop else { return false }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().path
            == desktop.resolvingSymlinksInPath().path
    }

    /// Moves a Desktop item into the folder and returns where it landed.
    static func moveIn(_ source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let destination = uniqueDestination(in: url, name: source.lastPathComponent)
        try coordinatedMove(from: source, to: destination)
        return destination
    }

    /// Returns an item to the Desktop under the name it had there, or a
    /// numbered variant if that name has since been taken.
    static func moveToDesktop(_ source: URL, name: String) throws -> URL {
        guard let desktop else {
            throw NSError(domain: "DesktopBinsWidget", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The Desktop folder could not be found."])
        }
        let destination = uniqueDestination(in: desktop, name: name)
        try coordinatedMove(from: source, to: destination)
        return destination
    }

    /// A move the file's owner is told about. The Desktop here belongs to
    /// OneDrive's file provider, and a coordinated move gives it the chance
    /// to fetch a cloud-only file before it leaves — an uncoordinated one
    /// could carry off a placeholder with no contents behind it.
    private static func coordinatedMove(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    /// "Report.pdf", then "Report 2.pdf", "Report 3.pdf" — never overwrite.
    private static func uniqueDestination(in directory: URL, name: String) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let url = directory.appendingPathComponent(numbered)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }
}
