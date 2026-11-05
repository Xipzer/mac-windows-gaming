import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Steam bundle")
struct SteamBundleTests {

    @Test("The process sweep covers the helpers as well as the bundle being modified")
    func sweepCoversHelpers() {
        let patterns = SteamBundle.sweepPatterns(
            app: SupportPaths.Steam.app, helpers: [SupportPaths.Steam.innerApp]
        )

        #expect(patterns.count == 2)
        #expect(patterns.contains("/Applications/Steam.app/"))
        #expect(
            patterns.contains { $0.hasSuffix("/Steam.AppBundle/Steam/") },
            "the inner bundle, where ipcserver and the helpers actually run, is not swept"
        )
    }

    @Test("Every pattern is directory-scoped")
    func patternsAreDirectoryScoped() {
        let patterns = SteamBundle.sweepPatterns(
            app: URL(filePath: "/tmp/Some.app"), helpers: [URL(filePath: "/tmp/Inner")]
        )

        #expect(patterns.allSatisfy { $0.hasSuffix("/") })
        #expect(patterns == ["/tmp/Some.app/", "/tmp/Inner/"])
    }

    @Test("Sweeping nothing is possible, so a test can stop short of killing helpers")
    func helpersCanBeEmpty() {
        let patterns = SteamBundle.sweepPatterns(app: URL(filePath: "/tmp/A.app"), helpers: [])
        #expect(patterns == ["/tmp/A.app/"])
    }

    private enum Insert {
        case absent
        case own
        case other(String)
    }

    private func stubBundle(insert: Insert, dylib: Bool) throws -> URL {
        let app = URL.temporaryDirectory
            .appending(path: "np-deploy-\(UUID().uuidString)")
            .appending(path: "Steam.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        var plist: [String: Any] = ["CFBundleIdentifier": "com.valvesoftware.steam"]
        switch insert {
        case .absent:
            break
        case .own:
            let own = SupportPaths.Steam.deployedDylib(inBundle: app)
            plist[SteamBundle.environmentKey] = [
                SteamBundle.insertKey: own.path(percentEncoded: false)
            ]
        case .other(let value):
            plist[SteamBundle.environmentKey] = [SteamBundle.insertKey: value]
        }
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))

        if dylib {
            try Data("stand-in\n".utf8).write(to: macOS.appending(path: SupportPaths.dylibName))
        }
        return app
    }

    private func versionFile(_ version: String?) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "dylib.version")
        if let version { try Data("\(version)\n".utf8).write(to: url) }
        return url
    }

    @Test("A bundle patched for this account with a matching version reads as installed")
    func installedForThisAccount() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile("0.2.0")
            ) == .installed(version: "0.2.0")
        )
    }

    @Test("A bundle patched by another account reports no version rather than a clean install")
    func patchedByAnotherAccount() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile(nil)
            ) == .installed(version: nil)
        )
    }

    @Test("A plist naming a dylib that is not there reads as not installed")
    func namedDylibMissing() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: false),
                versionFile: try versionFile("0.2.0")
            ) == .notInstalled
        )
    }

    @Test("An older recorded version reads as outdated")
    func outdatedVersion() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile("0.1.0")
            ) == .outdated(deployed: "0.1.0", bundled: "0.2.0")
        )
    }

    @Test("Somebody else's insert is left alone")
    func foreignInsert() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .other("/opt/other/thing.dylib"), dylib: true),
                versionFile: try versionFile(nil)
            ) == .foreign(insert: "/opt/other/thing.dylib")
        )
    }

    @Test("An unpatched bundle reads as not installed")
    func unpatched() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .absent, dylib: false),
                versionFile: try versionFile(nil)
            ) == .notInstalled
        )
    }

    @Test("A missing bundle reads as Steam missing")
    func steamMissing() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: URL.temporaryDirectory.appending(path: "np-absent-\(UUID().uuidString).app"),
                versionFile: try versionFile("0.2.0")
            ) == .steamMissing
        )
    }
}
