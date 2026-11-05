import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Runner patching")
struct RunnerPatcherTests {

    private static func healthyClone() throws -> (root: URL, build: RunnerBuild)? {
        let live = SupportPaths.currentRunner.resolvingSymlinksInPath()

        guard let id = RunnerStore.buildIdentifier(inPath: live.path(percentEncoded: false)),
              let build = SupportedRunners.build(id: id),
              RunnerPatcher.verify(build: build, root: live).isEmpty
        else { return nil }

        let scratch = URL(filePath: NSTemporaryDirectory())
            .appending(path: "steambridge-runner-\(UUID().uuidString)")
        let copied = try Shell.run("/bin/cp", [
            "-c", "-R", live.path(percentEncoded: false), scratch.path(percentEncoded: false),
        ])

        try #require(copied.status == 0)
        try #require(RunnerPatcher.verify(build: build, root: scratch).isEmpty)

        return (scratch, build)
    }

    @Test("A builtin the bridge has replaced is reported, then repaired by the install")
    func repairsStaleBuiltin() throws {
        guard let (root, build) = try Self.healthyClone() else { return }
        defer { try? FileManager.default.removeItem(at: root) }

        let arch = RunnerPatcher.unixArch(in: root)
        let builtin = root.appending(path: "lib/wine/\(arch)/lsteamclient.so")
        try Data("not the bridge copy".utf8).write(to: builtin)

        #expect(RunnerPatcher.verify(build: build, root: root)
            == ["\(arch)/lsteamclient.so is out of date"])

        let outcome = try RunnerPatcher.install(build: build, root: root)
        #expect(outcome.builtins == ["\(arch)/lsteamclient.so"])
        #expect(RunnerPatcher.verify(build: build, root: root).isEmpty)
    }

    @Test("A builtin that was never installed is reported, then repaired by the install")
    func repairsMissingBuiltin() throws {
        guard let (root, build) = try Self.healthyClone() else { return }
        defer { try? FileManager.default.removeItem(at: root) }

        let builtin = root.appending(path: "lib/wine/i386-windows/lsteamclient.dll")
        try FileManager.default.removeItem(at: builtin)

        #expect(RunnerPatcher.verify(build: build, root: root)
            == ["i386-windows/lsteamclient.dll is missing"])

        _ = try RunnerPatcher.install(build: build, root: root)
        #expect(RunnerPatcher.verify(build: build, root: root).isEmpty)
    }

    @Test("A runner back on stock ntdll is reported, then repaired by the install")
    func repairsStockNtdll() throws {
        guard let (root, build) = try Self.healthyClone() else { return }
        defer { try? FileManager.default.removeItem(at: root) }

        let arch = WineArch.x86_64Windows
        let live = root.appending(path: "lib/wine/\(arch.rawValue)/ntdll.dll")
        let clean = NtdllPatcher.cleanSource(inRoot: root, arch: arch)
        guard clean != live else { return }

        try Data(contentsOf: clean).write(to: live)
        #expect(RunnerPatcher.verify(build: build, root: root)
            == ["\(arch.rawValue)/ntdll.dll is not the patched copy"])

        let outcome = try RunnerPatcher.install(build: build, root: root)
        #expect(outcome.ntdll == [arch])
        #expect(Digest.sha256IfPresent(live) == build.patchedNtdll[arch])
        #expect(RunnerPatcher.verify(build: build, root: root).isEmpty)
    }

    @Test("A loader signed without the dyld entitlement is reported, then repaired")
    func repairsStrippedEntitlement() throws {
        guard let (root, build) = try Self.healthyClone() else { return }
        defer { try? FileManager.default.removeItem(at: root) }

        let loader = root.appending(path: "lib/wine/x86_64-unix/wine")
        let clean = Clean.copy(of: loader)
        guard clean != loader else { return }

        try #require(try Shell.run("/bin/cp", [
            "-p", clean.path(percentEncoded: false), loader.path(percentEncoded: false),
        ]).status == 0)

        #expect(RunnerPatcher.verify(build: build, root: root)
            == ["x86_64-unix/wine is missing the dyld entitlement"])

        let outcome = try RunnerPatcher.install(build: build, root: root)
        #expect(outcome.loaders == ["x86_64-unix/wine"])
        #expect(RunnerPatcher.verify(build: build, root: root).isEmpty)
    }

    @Test("Installing into a runner that is already right writes nothing")
    func installIsIdempotent() throws {
        guard let (root, build) = try Self.healthyClone() else { return }
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try RunnerPatcher.install(build: build, root: root)
        #expect(outcome.wroteNothing)
    }

    @Test("Loader discovery finds both the bare and the bundled layout")
    func loaderDiscoveryCoversBothLayouts() throws {
        let fm = FileManager.default
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-loaders-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let bundled = root.appending(path: "lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine")
        let bare = root.appending(path: "lib/wine/x86_64-unix/wine")
        for file in [bundled, bare] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }

        let windows = root.appending(path: "lib/wine/x86_64-windows/wine")
        try fm.createDirectory(at: windows.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: windows)

        let found = Set(RunnerPatcher.unixLoaders(in: root).map(RunnerPatcher.name(of:)))
        #expect(found == ["aarch64-unix/wine.app/Contents/MacOS/wine", "x86_64-unix/wine"])
    }

    @Test("The unix builtin follows the loader RUN_SCRIPT picks")
    func unixBuiltinFollowsTheLoader() throws {
        let fm = FileManager.default
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-unixarch-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        func write(_ path: String) throws {
            let file = root.appending(path: path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }

        try write("lib/wine/x86_64-unix/wine")
        #expect(RunnerPatcher.unixArch(in: root) == "x86_64-unix")

        try write("lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine")
        #expect(RunnerPatcher.unixArch(in: root) == "aarch64-unix")

        let arches = RunnerPatcher.builtins(in: root).map(\.arch)
        #expect(arches == RunnerPatcher.windowsBuiltins.map(\.arch) + ["aarch64-unix"])
        #expect(RunnerPatcher.builtins(in: root).allSatisfy { $0.name.hasPrefix("lsteamclient") })
    }
}
