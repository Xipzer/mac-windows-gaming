import Foundation
import Testing

@testable import SteamBridgeApp

enum RealPrefixes {
    static var library: SteamLibrary {
        SteamLibrary(root: URL(filePath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Steam"))
    }

    static var candidates: [WinePrefix] {
        let loader = PrefixTools.layout(runner: SupportPaths.currentRunner).unixDir
        guard FileManager.default.fileExists(
            atPath: loader.path(percentEncoded: false)) else { return [] }
        func realDirectory(_ url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            return values?.isSymbolicLink != true && values?.isDirectory == true
        }
        var real: WinePrefix?
        var linked: WinePrefix?
        var split: WinePrefix?
        for prefix in PrefixStore.all(libraries: [library]) where !PrefixStore.isInUse(prefix) {
            let users = prefix.pfx.appending(path: "drive_c/users")
            let steamuser = users.appending(path: "steamuser")
            guard FileManager.default.fileExists(
                atPath: prefix.pfx.appending(path: "user.reg").path(percentEncoded: false)
            ) else { continue }
            guard let values = try? steamuser.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { continue }
            if values.isSymbolicLink == true {
                linked = linked ?? prefix
            } else if values.isDirectory == true {
                if realDirectory(users.appending(path: "crossover")) {
                    split = split ?? prefix
                } else {
                    real = real ?? prefix
                }
            }
        }
        return [real, linked, split].compactMap { $0 }
    }
}

@Suite("Real rebuild", .serialized, .enabled(if: !RealPrefixes.candidates.isEmpty))
struct RealRebuildTests {
    private func clone(_ prefix: WinePrefix) throws -> WinePrefix {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appending(path: "realrebuild-\(prefix.appID)-\(UUID().uuidString)")
        let library = SteamLibrary(root: dir)
        try FileManager.default.createDirectory(
            at: library.compatdata, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: prefix.root, to: library.compatdata.appending(path: prefix.appID))
        return WinePrefix(appID: prefix.appID, name: prefix.name, library: library, lastUsed: nil)
    }

    private func inventory(_ pfx: URL) -> (files: [String], links: [String]) {
        let fm = FileManager.default
        let users = pfx.appending(path: "drive_c/users").resolvingSymlinksInPath()
        let base = users.path(percentEncoded: false) + "/"
        var files: [String] = []
        var links: [String] = []
        let walker = fm.enumerator(
            at: users, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        while let entry = walker?.nextObject() as? URL {
            let full = entry.resolvingSymlinksInPath().path(percentEncoded: false)
            let path = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                links.append(path)
            } else if values?.isDirectory != true {
                files.append(path)
            }
        }
        return (files.sorted(), links.sorted())
    }

    @Test("A real rebuild keeps every profile file and lands on the steamuser layout")
    func realRebuildKeepsBothProfiles() throws {
        for original in RealPrefixes.candidates {
            let prefix = try clone(original)
            defer { try? FileManager.default.removeItem(at: prefix.library.root) }

            let before = inventory(prefix.pfx)
            let registry = try Data(contentsOf: prefix.pfx.appending(path: "user.reg"))

            let stray = prefix.pfx.appending(path: "drive_c/Games/Quake/quake.exe")
            try FileManager.default.createDirectory(
                at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("exe".utf8).write(to: stray)

            try PrefixTools.recreate(prefix)
            let after = inventory(prefix.pfx)

            func normalised(_ paths: [String]) -> Set<String> {
                Set(paths.map { path in
                    var parts = path.split(separator: "/").map(String.init)
                    guard !parts.isEmpty else { return path }
                    parts = parts.map { $0.replacing(#/ BACKUP( \d+)?$/#, with: "") }
                    parts[0] = "profile"
                    if parts.count > 1, ["Documents", "My Documents"].contains(parts[1]) {
                        parts[1] = "documents"
                    }
                    return parts.joined(separator: "/")
                })
            }
            #expect(normalised(after.files) == normalised(before.files),
                    "\(prefix.appID) lost profile files")
            #expect(try Data(contentsOf: prefix.pfx.appending(path: "user.reg")) == registry)
            #expect(try Data(contentsOf: stray) == Data("exe".utf8), "\(prefix.appID) lost C:\\Games")

            let users = prefix.pfx.appending(path: "drive_c/users")
            let crossover = users.appending(path: "crossover")
            let steamuser = users.appending(path: "steamuser")
            #expect(try FileManager.default.destinationOfSymbolicLink(
                atPath: crossover.path(percentEncoded: false)) == "steamuser")
            #expect((try? steamuser.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink != true)

            let documents = steamuser.appending(path: "Documents")
            let preVista = steamuser.appending(path: "My Documents")
            for name in [documents, preVista] {
                var resolved = ObjCBool(false)
                #expect(FileManager.default.fileExists(
                    atPath: name.path(percentEncoded: false), isDirectory: &resolved))
                #expect(resolved.boolValue)
            }

            let inside = prefix.pfx.resolvingSymlinksInPath().path(percentEncoded: false)
            for folder in ["Documents", "My Documents", "Downloads", "Music", "Pictures", "Videos"] {
                let resolved = steamuser.appending(path: folder)
                    .resolvingSymlinksInPath().path(percentEncoded: false)
                #expect(resolved.hasPrefix(inside),
                        "\(prefix.appID) resolves \(folder) to \(resolved)")
            }

            let ntdll = prefix.pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
            #expect(PrefixStore.arch(of: prefix) == PrefixTools.prefixArch())
            #expect(FileManager.default.fileExists(atPath: ntdll.path(percentEncoded: false)))
        }
    }
}
