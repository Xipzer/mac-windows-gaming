import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Prefix store")
struct PrefixStoreTests {

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "np-pfx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test("Every library path in the file is found, in order, without duplicates")
    func readsLibraryPaths() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vdf = dir.appending(path: "libraryfolders.vdf")
        try write(
            """
            "libraryfolders"
            {
            \t"0"
            \t{
            \t\t"path"\t\t"/Users/tester/Library/Application Support/Steam"
            \t\t"label"\t\t""
            \t\t"apps"
            \t\t{
            \t\t\t"480"\t\t"1906055"
            \t\t}
            \t}
            \t"1"
            \t{
            \t\t"path"\t\t"/Volumes/External Games SSD/SteamLibrary"
            \t\t"label"\t\t""
            \t}
            }
            """, to: vdf)

        let libraries = PrefixStore.libraries(vdf: vdf)
        #expect(libraries.count == 2)
        #expect(libraries.first?.root.path(percentEncoded: false) == "/Users/tester/Library/Application Support/Steam")
        #expect(libraries.last?.root.lastPathComponent == "SteamLibrary")
        #expect(libraries.last?.root.path(percentEncoded: false) == "/Volumes/External Games SSD/SteamLibrary")
        #expect(libraries.last?.compatdata.lastPathComponent == "compatdata")
    }

    @Test("A missing or empty file still yields the default library")
    func fallsBackToTheDefaultLibrary() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = PrefixStore.libraries(vdf: dir.appending(path: "nothing.vdf"))
        #expect(missing.count == 1)
        #expect(missing.first?.root == SupportPaths.Steam.userData)

        let empty = dir.appending(path: "empty.vdf")
        try write("\"libraryfolders\"\n{\n}\n", to: empty)
        #expect(PrefixStore.libraries(vdf: empty).first?.root == SupportPaths.Steam.userData)
    }

    @Test("An entry without a pfx is not a prefix")
    func skipsEntriesWithoutAPrefix() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)
        try write("", to: library.compatdata.appending(path: "9999"))

        let prefixes = PrefixStore.all(libraries: [library])
        #expect(prefixes.map(\.appID) == ["1574480"])
    }

    @Test("A name comes from the library's own appmanifest, and its absence is not a failure")
    func readsTheAppName() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1649240/pfx"), withIntermediateDirectories: true)
        try write(
            """
            "AppState"
            {
            \t"appid"\t\t"1574480"
            \t"name"\t\t"Agent 64: Spies Never Die"
            }
            """, to: library.steamapps.appending(path: "appmanifest_1574480.acf"))

        let prefixes = PrefixStore.all(libraries: [library])
        let named = prefixes.first { $0.appID == "1574480" }
        let orphan = prefixes.first { $0.appID == "1649240" }

        #expect(named?.name == "Agent 64: Spies Never Die")
        #expect(named?.title == "Agent 64: Spies Never Die")
        #expect(orphan?.name == nil)
        #expect(orphan?.title == "App 1649240")
    }

    @Test("Sizing a prefix stops at a symlink instead of walking through it")
    func doesNotFollowLinksOutOfThePrefix() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        let outside = dir.appending(path: "outside-the-prefix")
        try write("host file one", to: outside.appending(path: "one.txt"))
        try write("host file two", to: outside.appending(path: "two.txt"))

        let profile = library.compatdata.appending(path: "1574480/pfx/drive_c/users/crossover")
        try write("in prefix", to: profile.appending(path: "AppData/Roaming/game/save.dat"))
        try FileManager.default.createSymbolicLink(
            at: profile.appending(path: "Documents"), withDestinationURL: outside)

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        let usage = PrefixStore.usage(of: prefix)

        #expect(usage.profileFiles == 1)
        #expect(usage.bytes > 0)
    }

    @Test("Only the parked prefixes count as backups")
    func backupsIgnoreEverythingElseInTheEntry() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)
        let fm = FileManager.default

        let entry = library.compatdata.appending(path: "1574480")
        for folder in ["pfx", "pfx.rebuild", "steambridge-msync",
                       "pfx.previous-20260101-120000", "pfx.previous-20260102-133000"] {
            try fm.createDirectory(
                at: entry.appending(path: folder), withIntermediateDirectories: true)
        }
        try write("not a prefix", to: entry.appending(path: "pfx.previous-note.txt"))

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)

        #expect(PrefixStore.backups(of: prefix).map(\.lastPathComponent)
            == ["pfx.previous-20260101-120000", "pfx.previous-20260102-133000"])
    }

    @Test("Backing up a prefix copies it into a listed slot and leaves the prefix alone")
    func backUpCopiesTheLivePrefix() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = try prefix(in: dir)
        try write("save", to: prefix.pfx.appending(path: "user.reg"))
        let taken = try #require(PrefixStore.backupClock().date(from: "20260101-120000"))

        let slot = try PrefixTools.backUp(prefix, now: taken)

        #expect(slot.lastPathComponent == "pfx.previous-20260101-120000")
        #expect(PrefixStore.backups(of: prefix).map(\.lastPathComponent)
            == ["pfx.previous-20260101-120000"])
        #expect(try String(contentsOf: slot.appending(path: "user.reg"), encoding: .utf8) == "save")
        #expect(
            try String(contentsOf: prefix.pfx.appending(path: "user.reg"), encoding: .utf8)
                == "save")
    }

    @Test("Backing up refuses a game that has never made a prefix")
    func backUpRefusesAMissingPrefix() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = try prefix(in: dir)
        try FileManager.default.removeItem(at: prefix.pfx)

        let refusal = try #require(throws: StepFailure.self) { try PrefixTools.backUp(prefix) }
        #expect(refusal.detail.hasPrefix(prefix.title))
        #expect(refusal.detail.hasSuffix("."))
        #expect(PrefixStore.backups(of: prefix).isEmpty)
    }

    @Test("A backup carries the time in its name back out as a date")
    func backupDetailsReadTheStamp() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        let entry = library.compatdata.appending(path: "1574480")
        try write("live", to: entry.appending(path: "pfx/drive_c/users/crossover/save.dat"))
        try write("older", to: entry.appending(path: "pfx.previous-20260101-120000/user.reg"))
        try write("newer", to: entry.appending(path: "pfx.previous-20260102-133000-2/user.reg"))

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        let details = PrefixStore.backupDetails(of: prefix)

        #expect(details.count == 2)
        #expect(details.allSatisfy { $0.bytes > 0 })
        #expect(details.map(\.prefix) == [prefix, prefix])

        let clock = PrefixStore.backupClock()
        #expect(details[0].taken == clock.date(from: "20260101-120000"))
        #expect(details[1].taken == clock.date(from: "20260102-133000"))
        #expect(PrefixStore.usage(of: prefix).profileFiles == 1)
    }

    @Test("A parked prefix with no readable stamp still lists, without a date")
    func backupWithoutAStampHasNoDate() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        let entry = library.compatdata.appending(path: "1574480")
        try write("live", to: entry.appending(path: "pfx/user.reg"))
        try write("old", to: entry.appending(path: "pfx.previous/user.reg"))

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        let details = PrefixStore.backupDetails(of: prefix)

        #expect(details.count == 1)
        #expect(details[0].taken == nil)
        #expect(PrefixStore.backupDate(of: details[0].url) == nil)
    }

    @Test("A library on the boot volume is named by its folder alone")
    func bootVolumeLibraryIsNotQualified() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = PrefixStore.library(at: dir)
        #expect(library.volume == nil)
        #expect(library.displayName == dir.lastPathComponent)
        #expect(PrefixStore.volumeName(of: dir) == nil)
    }

    @Test("A library on another drive is named by the drive alone")
    func externalLibraryNamesTheDrive() {
        let root = URL(filePath: "/Volumes/External Games SSD/SteamLibrary")
        let library = SteamLibrary(root: root, volume: "External Games SSD")

        #expect(library.displayName == "External Games SSD")
        #expect(SteamLibrary(root: root).displayName == "SteamLibrary")
    }

    @Test("A prefix points at the game's install folder while the game is installed")
    func findsTheInstallDirectory() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)

        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)
        try write(
            """
            "AppState"
            {
            \t"appid"\t\t"1574480"
            \t"installdir"\t\t"Agent 64"
            }
            """, to: library.steamapps.appending(path: "appmanifest_1574480.acf"))

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        #expect(PrefixStore.installDirectory(of: prefix) == nil)

        let installed = library.steamapps.appending(path: "common/Agent 64")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        #expect(
            PrefixStore.installDirectory(of: prefix)?.path(percentEncoded: false)
                == installed.path(percentEncoded: false))
    }

    private func writeNtdll(machine: UInt16?, in pfx: URL, lfanew: UInt32 = 0x40) throws {
        var bytes = [UInt8](repeating: 0, count: 0x40)
        withUnsafeBytes(of: lfanew.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        if let machine {
            bytes += [0x50, 0x45, 0x00, 0x00]
            bytes += withUnsafeBytes(of: machine.littleEndian) { Array($0) }
        }
        let dll = pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
        try FileManager.default.createDirectory(
            at: dll.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: dll)
    }

    private func prefix(in dir: URL) throws -> WinePrefix {
        let library = SteamLibrary(root: dir)
        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)
        return try #require(PrefixStore.all(libraries: [library]).first)
    }

    @Test("A prefix names the compatibility tool that built it through its own ntdll")
    func readsPrefixArch() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = try prefix(in: dir)

        for (machine, expected) in [
            (UInt16(0xaa64), PrefixArch.arm64),
            (UInt16(0x8664), PrefixArch.x86_64),
            (UInt16(0x014c), PrefixArch.i386),
        ] {
            try writeNtdll(machine: machine, in: prefix.pfx)
            #expect(PrefixStore.arch(of: prefix) == expected)
        }
    }

    @Test("An unreadable header is no arch rather than a wrong one")
    func unreadableArchIsNil() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = try prefix(in: dir)

        #expect(PrefixStore.arch(of: prefix) == nil)

        try writeNtdll(machine: 0x1234, in: prefix.pfx)
        #expect(PrefixStore.arch(of: prefix) == nil)

        try writeNtdll(machine: 0xaa64, in: prefix.pfx, lfanew: 0x40000)
        #expect(PrefixStore.arch(of: prefix) == nil)

        try writeNtdll(machine: nil, in: prefix.pfx)
        #expect(PrefixStore.arch(of: prefix) == nil)

        let dll = prefix.pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
        try write("just text", to: dll)
        #expect(PrefixStore.arch(of: prefix) == nil)

        var stub = [UInt8](repeating: 0, count: 0x40)
        withUnsafeBytes(of: UInt32(0x40).littleEndian) { stub.replaceSubrange(0x3c..<0x40, with: $0) }
        stub += [0x4d, 0x5a, 0x00, 0x00, 0x64, 0x86]
        try Data(stub).write(to: dll)
        #expect(PrefixStore.arch(of: prefix) == nil)
    }

    @Test("An idle prefix is not reported as in use")
    func idlePrefixIsNotInUse() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SteamLibrary(root: dir)
        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)

        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        #expect(PrefixStore.serverDirectory(of: prefix) != nil)
        #expect(PrefixStore.isInUse(prefix) == false)
    }

    private func prefixWithServerDirectory() throws -> (WinePrefix, URL, URL) {
        let dir = try tempDirectory()
        let library = SteamLibrary(root: dir)
        try FileManager.default.createDirectory(
            at: library.compatdata.appending(path: "1574480/pfx"), withIntermediateDirectories: true)
        let prefix = try #require(PrefixStore.all(libraries: [library]).first)
        let root = dir.appending(path: "wine-sockets")
        let socket = try #require(PrefixStore.serverDirectory(of: prefix, root: root))
        try FileManager.default.createDirectory(at: socket, withIntermediateDirectories: true)
        return (prefix, root, dir)
    }

    private func stubLsof(in dir: URL, body: String) throws -> String {
        let path = dir.appending(path: "lsof")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: path.path(percentEncoded: false))
        return path.path(percentEncoded: false)
    }

    @Test("A prefix whose socket directory is held open is reported as in use")
    func heldPrefixIsInUse() throws {
        let (prefix, root, dir) = try prefixWithServerDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let held = try #require(PrefixStore.serverDirectory(of: prefix, root: root))
            .appending(path: "socket")
        try Data("s".utf8).write(to: held)
        let handle = try FileHandle(forReadingFrom: held)
        defer { try? handle.close() }

        #expect(PrefixStore.isInUse(prefix, root: root))
    }

    @Test("lsof failing to answer is not read as the prefix being free")
    func anUnusableLsofIsNotReadAsFree() throws {
        let (prefix, root, dir) = try prefixWithServerDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(PrefixStore.isInUse(
            prefix, root: root, lsof: dir.appending(path: "absent").path(percentEncoded: false)))

        #expect(PrefixStore.isInUse(
            prefix, root: root,
            lsof: try stubLsof(in: dir, body: "echo trouble >&2; exit 1")))

        #expect(PrefixStore.isInUse(
            prefix, root: root,
            lsof: try stubLsof(in: dir, body: "sleep 3 & exit 1"),
            drainTimeout: .milliseconds(200)))
    }

    @Test("An idle socket directory is still reported as free")
    func anIdleSocketDirectoryIsFree() throws {
        let (prefix, root, dir) = try prefixWithServerDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(PrefixStore.isInUse(prefix, root: root) == false)
    }
}
