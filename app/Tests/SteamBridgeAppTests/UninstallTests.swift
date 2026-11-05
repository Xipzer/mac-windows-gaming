import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Uninstall")
struct UninstallTests {

    private final class PhaseLog: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [UninstallPhase] = []
        func add(_ phase: UninstallPhase) { lock.lock(); seen.append(phase); lock.unlock() }
        var all: [UninstallPhase] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private struct Layout: Sendable {
        let root: URL
        let app: URL
        let innerPlist: URL
        let updateBlock: URL
        let legacyCompat: URL
        let compatTool: URL
        let support: URL
        let caches: URL

        var outerPlist: URL { app.appending(path: "Contents/Info.plist") }
        var dylib: URL { app.appending(path: "Contents/MacOS/\(SupportPaths.dylibName)") }
    }

    private func layout(signable: Bool = false) throws -> Layout {
        let files = FileManager.default
        let root = URL.temporaryDirectory.appending(path: "np-uninstall-\(UUID().uuidString)")
        let app = root.appending(path: "Steam.app")
        let macOS = app.appending(path: "Contents/MacOS")
        let inner = root.appending(path: "inner")
        let legacyCompat = inner.appending(path: "legacycompat")
        let compatTool = root.appending(path: "compatibilitytools.d/steambridge")
        let support = root.appending(path: "steambridge")
        let caches = root.appending(path: "valve-packages")

        for dir in [macOS, inner, legacyCompat, compatTool, support, caches] {
            try files.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let updateBlock = root.appending(path: "steam.cfg")
        try Data("BootStrapperInhibitAll=enable\nBootStrapperInhibitUpdateOnLaunch=enable\n".utf8)
            .write(to: updateBlock)
        try Data("1\n".utf8).write(to: support.appending(path: "dylib.version"))
        try Data("archive\n".utf8).write(to: caches.appending(path: "steam_client_osx.zip"))
        try Data("\"run\"\n".utf8).write(to: compatTool.appending(path: "toolmanifest.vdf"))

        let result = Layout(
            root: root,
            app: app,
            innerPlist: inner.appending(path: "Info.plist"),
            updateBlock: updateBlock,
            legacyCompat: legacyCompat,
            compatTool: compatTool,
            support: support,
            caches: caches
        )

        guard signable else { return result }

        let source = root.appending(path: "main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: source)
        try Shell.check("/usr/bin/clang", [
            "-o", macOS.appending(path: "steam_osx").path(percentEncoded: false),
            source.path(percentEncoded: false),
        ])
        try Shell.check("/usr/bin/clang", [
            "-dynamiclib",
            "-o", result.dylib.path(percentEncoded: false),
            source.path(percentEncoded: false),
        ])

        let injected: [String: Any] = [
            "CFBundleExecutable": "steam_osx",
            "CFBundleIdentifier": "com.valvesoftware.steam",
            SteamBundle.environmentKey: [
                "LC_ALL": "C",
                SteamBundle.insertKey: result.dylib.path(percentEncoded: false),
            ],
        ]
        try SteamBundle.writeInfoPlist(injected, at: result.outerPlist)
        try SteamBundle.writeInfoPlist(injected, at: result.innerPlist)
        try SteamInstaller.adHocSign(app)

        return result
    }

    @Test("Detaching leaves a Steam that loads nothing of ours")
    func takesEverythingOfOursOutOfTheBundle() throws {
        let layout = try layout(signable: true)
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let files = FileManager.default

        let detached = try Uninstall.detach(
            from: layout.app,
            innerPlist: layout.innerPlist,
            updateBlocks: [layout.updateBlock]
        )

        #expect(detached)
        #expect(SteamBundle.currentInsert(at: layout.outerPlist) == nil)
        #expect(SteamBundle.currentInsert(at: layout.innerPlist) == nil)
        #expect(!files.fileExists(atPath: layout.dylib.path(percentEncoded: false)))
        #expect(unpinnedWithoutLosingTheRest(layout.updateBlock))

        let environment = SteamBundle.readInfoPlist(at: layout.outerPlist)?[
            SteamBundle.environmentKey
        ] as? [String: Any]
        #expect(environment?["LC_ALL"] as? String == "C")

        let verified = try Shell.run("/usr/bin/codesign", [
            "--verify", "--deep", layout.app.path(percentEncoded: false),
        ])
        #expect(verified.succeeded)
    }

    private func unpinnedWithoutLosingTheRest(_ cfg: URL) -> Bool {
        guard let text = try? String(contentsOf: cfg, encoding: .utf8) else { return false }
        return !UpdateBlock.isPresent(at: [cfg]) && text.contains("BootStrapperInhibitAll=enable")
    }

    private func verifies(_ app: URL) throws -> Bool {
        try Shell.run("/usr/bin/codesign", [
            "--verify", "--deep", app.path(percentEncoded: false),
        ]).succeeded
    }

    @Test("A removal that fails outside the bundle leaves the bundle alone")
    func failureOutsideTheBundleLeavesItSigned() throws {
        let files = FileManager.default
        let layout = try layout(signable: true)
        defer { try? FileManager.default.removeItem(at: layout.root) }
        try files.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: layout.updateBlock.path(percentEncoded: false))
        defer {
            try? files.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: layout.updateBlock.path(percentEncoded: false))
        }

        #expect(throws: WriteRefused.self) {
            try Uninstall.detach(
                from: layout.app, innerPlist: layout.innerPlist, updateBlocks: [layout.updateBlock])
        }

        #expect(SteamBundle.currentInsert(at: layout.outerPlist) != nil)
        #expect(try verifies(layout.app))
    }

    @Test("A removal that fails inside the bundle still signs it")
    func failureInsideTheBundleStillSignsIt() throws {
        let layout = try layout(signable: true)
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let dylib = layout.dylib.path(percentEncoded: false)
        try Shell.check("/usr/bin/chflags", ["uchg", dylib])
        defer { _ = try? Shell.check("/usr/bin/chflags", ["nouchg", dylib]) }

        #expect(throws: (any Error).self) {
            try Uninstall.detach(
                from: layout.app, innerPlist: layout.innerPlist, updateBlocks: [layout.updateBlock])
        }

        #expect(SteamBundle.currentInsert(at: layout.outerPlist) == nil)
        #expect(try verifies(layout.app))
    }

    @Test("A restore that fails does not cancel the removal")
    func removesEverythingWhenSteamCannotBeRestored() async throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        struct Offline: Error {}

        let outcome = try await Uninstall.run(
            app: layout.app,
            innerPlist: layout.innerPlist,
            updateBlocks: [layout.updateBlock],
            legacyCompat: layout.legacyCompat,
            compatTool: layout.compatTool,
            directories: [layout.support, layout.caches],
            repair: { _ in throw Offline() },
            stop: { _ in false }
        )

        #expect(outcome.restoredValveSignature == false)

        let files = FileManager.default
        #expect(!files.fileExists(atPath: layout.support.path(percentEncoded: false)))
        #expect(!files.fileExists(atPath: layout.caches.path(percentEncoded: false)))
        #expect(!files.fileExists(atPath: layout.legacyCompat.path(percentEncoded: false)))
        #expect(
            !files.fileExists(atPath: layout.compatTool.path(percentEncoded: false)),
            "Steam would still list the tool in its dropdown after a removal"
        )
        #expect(unpinnedWithoutLosingTheRest(layout.updateBlock))
    }

    @Test("The copy the restore downloads is removed with everything else")
    func removesWhatTheRestoreLeavesBehind() async throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let caches = layout.caches
        try FileManager.default.removeItem(at: caches)

        let outcome = try await Uninstall.run(
            app: layout.app,
            innerPlist: layout.innerPlist,
            updateBlocks: [layout.updateBlock],
            legacyCompat: layout.legacyCompat,
            compatTool: layout.compatTool,
            directories: [layout.support, caches],
            repair: { _ in
                let staged = caches.appending(path: "bundle")
                try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
                try Data("2.6G of Steam".utf8).write(to: staged.appending(path: "Steam.app"))
            },
            stop: { _ in false }
        )

        #expect(outcome.restoredValveSignature)
        #expect(!FileManager.default.fileExists(atPath: caches.path(percentEncoded: false)))
    }

    @Test("A removal reports the repair's own phases while it restores")
    func reportsTheRepairPhases() async throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }

        let log = PhaseLog()
        _ = try await Uninstall.run(
            app: layout.app,
            innerPlist: layout.innerPlist,
            updateBlocks: [layout.updateBlock],
            legacyCompat: layout.legacyCompat,
            compatTool: layout.compatTool,
            directories: [layout.support, layout.caches],
            report: { log.add($0) },
            repair: { report in
                report(.checking)
                report(.replacing)
            },
            stop: { _ in false }
        )

        let restoring = log.all.compactMap { phase -> RepairPhase? in
            if case .restoring(let inner) = phase { inner } else { nil }
        }
        #expect(restoring.count == 2)
        #expect(restoring.contains { if case .checking = $0 { true } else { false } })
        #expect(restoring.contains { if case .replacing = $0 { true } else { false } })

        let labels = log.all.map(\.label)
        #expect(labels.contains(RepairPhase.checking.label))
        #expect(labels.contains(RepairPhase.replacing.label))
    }

}
