import Foundation
import Testing

@testable import SteamBridgeApp

private final class Libraries: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [SteamLibrary]

    init(_ value: [SteamLibrary]) { self.value = value }

    var current: [SteamLibrary] {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var order: [String] = []
    private var clashed = false
    private let held: DispatchSemaphore?

    init(holdingEachTurn: Bool = false) {
        held = holdingEachTurn ? DispatchSemaphore(value: 0) : nil
    }

    struct Refused: LocalizedError {
        let appID: String
        var errorDescription: String? { "\(appID) refused" }
    }

    var visited: [String] { lock.withLock { order } }
    var overlapped: Bool { lock.withLock { clashed } }

    func releaseTurn() { held?.signal() }

    static func backup(of prefix: WinePrefix) -> URL {
        prefix.root.appending(path: "pfx.previous-20260101-120000")
    }

    @discardableResult
    func enter(_ prefix: WinePrefix, failing: Bool = false) throws -> URL? {
        lock.withLock {
            order.append(prefix.title)
            inFlight += 1
            if inFlight > 1 { clashed = true }
        }
        defer { lock.withLock { inFlight -= 1 } }
        if let held {
            held.wait()
        } else {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if failing { throw Refused(appID: prefix.appID) }
        return Self.backup(of: prefix)
    }
}

@MainActor
@Suite("Loading prefixes")
struct PrefixesModelTests {

    private func makeLibrary(appIDs: [String]) throws -> (URL, SteamLibrary) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "np-model-\(UUID().uuidString)")
        let library = SteamLibrary(root: dir)
        for appID in appIDs {
            try FileManager.default.createDirectory(
                at: library.compatdata.appending(path: "\(appID)/pfx/drive_c/users/crossover"),
                withIntermediateDirectories: true)
        }
        return (dir, library)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func writeNtdll(machine: UInt16, in pfx: URL) throws {
        var bytes = [UInt8](repeating: 0, count: 0x40)
        withUnsafeBytes(of: UInt32(0x40).littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        bytes += [0x50, 0x45, 0x00, 0x00]
        bytes += withUnsafeBytes(of: machine.littleEndian) { Array($0) }
        let dll = pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
        try FileManager.default.createDirectory(
            at: dll.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: dll)
    }

    @Test("A prefix built by the other compatibility tool is the only one flagged")
    func flagsForeignPrefixes() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "253750", "447700"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let compatdata = library.compatdata
        try writeNtdll(machine: 0xaa64, in: compatdata.appending(path: "1574480/pfx"))
        try writeNtdll(machine: 0x8664, in: compatdata.appending(path: "253750/pfx"))

        let model = PrefixesModel(libraries: { [library] }, runnerArch: { .arm64 })
        await model.load()

        func prefix(_ appID: String) throws -> WinePrefix {
            try #require(model.prefixes.first { $0.appID == appID })
        }
        #expect(model.expectedArch == .arm64)
        #expect(model.isForeign(try prefix("1574480")) == false)
        #expect(model.isForeign(try prefix("253750")) == true)
        #expect(model.isForeign(try prefix("447700")) == false)
    }

    @Test("A load lists the prefixes and measures each one")
    func loadsAndMeasures() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PrefixesModel(libraries: { [library] })

        await model.load()

        #expect(model.prefixes.count == 2)
        #expect(Set(model.usage.keys) == Set(model.prefixes.map(\.id)))
        #expect(!model.isLoading)
    }

    @Test("A load that is superseded does not publish into the newer one")
    func supersededLoadPublishesNothing() async throws {
        let (oldDir, oldLibrary) = try makeLibrary(appIDs: ["1574480", "1649240", "3014330"])
        defer { try? FileManager.default.removeItem(at: oldDir) }
        let (newDir, newLibrary) = try makeLibrary(appIDs: ["4401430"])
        defer { try? FileManager.default.removeItem(at: newDir) }

        let libraries = Libraries([oldLibrary])
        let model = PrefixesModel(libraries: { libraries.current })

        let first = Task { await model.load() }
        await Task.yield()

        libraries.current = [newLibrary]
        let replacement = Task { await model.load() }

        _ = await first.value
        _ = await replacement.value

        #expect(Set(model.usage.keys) == Set(model.prefixes.map(\.id)))
        #expect(!model.isLoading)
    }

    @Test("Loading again from a changed library replaces the previous results")
    func reloadReplacesResults() async throws {
        let (oldDir, oldLibrary) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: oldDir) }
        let (newDir, newLibrary) = try makeLibrary(appIDs: ["4401430"])
        defer { try? FileManager.default.removeItem(at: newDir) }

        let libraries = Libraries([oldLibrary])
        let model = PrefixesModel(libraries: { libraries.current })

        await model.load()
        #expect(model.prefixes.count == 2)

        libraries.current = [newLibrary]
        await model.load()

        #expect(model.prefixes.map(\.appID) == ["4401430"])
        #expect(Set(model.usage.keys) == Set(model.prefixes.map(\.id)))
        #expect(!model.isLoading)
    }

    @Test("A load drops selected prefixes that are no longer there")
    func loadPrunesStaleSelection() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(libraries: { [library] })
        await model.load()

        let survivor = try #require(model.prefixes.first { $0.appID == "1649240" })
        let doomed = try #require(model.prefixes.first { $0.appID == "1574480" })
        model.selection = [survivor.id, doomed.id]

        try FileManager.default.removeItem(at: library.compatdata.appending(path: "1574480"))
        await model.load()

        #expect(model.prefixes.count == 1)
        #expect(!model.selection.contains(doomed.id))
        #expect(model.selection.count == 1)
    }

    @Test("Only a single selected prefix is a target for the per-prefix actions")
    func selectedPrefixIsSingleSelectionOnly() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PrefixesModel(libraries: { [library] })
        await model.load()

        #expect(model.selectedPrefix == nil)

        let one = try #require(model.prefixes.first)
        model.selection = [one.id]
        #expect(model.selectedPrefix == one)

        model.selection = Set(model.prefixes.map(\.id))
        #expect(model.selection.count == 2)
        #expect(model.selectedPrefix == nil)
    }

    @Test("Declining the backup tells the rebuild not to keep one")
    func rebuildForwardsTheBackupChoice() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(
            libraries: { [library] },
            rebuild: { prefix, keep in keep ? Recorder.backup(of: prefix) : nil })
        await model.load()
        let targets = model.prefixes
        let title = try #require(targets.first).title

        await model.recreate(targets, keepBackup: false)
        #expect(model.outcome == "Rebuilt the prefix for \(title).")

        await model.recreate(targets)
        #expect(model.outcome?.contains("The original is at") == true)
    }

    @Test("Backing up reports where the copy landed")
    func backUpReportsTheSlot() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(
            libraries: { [library] }, makeBackup: { Recorder.backup(of: $0) })
        await model.load()
        let targets = model.prefixes
        let first = try #require(targets.first)

        await model.backUp([first])
        #expect(model.outcome == "Backed up the prefix for \(first.title).")
        #expect(model.failure == nil)

        await model.backUp(targets)
        #expect(model.outcome == "Backed up 2 prefixes.")
    }

    @Test("Rebuilding takes every selected prefix, one after another")
    func rebuildTakesTheWholeSelection() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240", "253750"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = Recorder()
        let model = PrefixesModel(
            libraries: { [library] }, rebuild: { prefix, _ in try log.enter(prefix) })
        await model.load()
        model.selection = Set(model.prefixes.map(\.id))

        let targets = model.selectedPrefixes
        #expect(targets.count == 3)
        await model.recreate(targets)

        #expect(log.visited == targets.map(\.title))
        #expect(!log.overlapped)
        #expect(model.outcome == "Rebuilt 3 prefixes. Each original is kept beside the game's "
            + "prefix. Check that your saves are present in the games, then delete the backups "
            + "to save space.")
        #expect(model.failure == nil)
        #expect(model.busy.isEmpty)
        #expect(!model.isBusy)
    }

    @Test("A prefix that refuses to rebuild does not stop the ones queued behind it")
    func rebuildReportsAPartialRun() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240", "253750"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = Recorder()
        let model = PrefixesModel(
            libraries: { [library] },
            rebuild: { prefix, _ in try log.enter(prefix, failing: prefix.appID == "1649240") }
        )
        await model.load()
        let targets = model.prefixes
        await model.recreate(targets)

        #expect(log.visited.count == 3)
        #expect(model.outcome == "Rebuilt 2 prefixes. Each original is kept beside the game's "
            + "prefix. Check that your saves are present in the games, then delete the backups "
            + "to save space.")
        #expect(model.failure == "1649240 refused")
        #expect(model.busy.isEmpty)
    }

    @Test("A refused rebuild reaches the pane with its remedy intact")
    func rebuildCarriesTheRemedy() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(
            libraries: { [library] },
            rebuild: { prefix, _ in
                throw WriteRefused(path: prefix.root.path(percentEncoded: false))
            }
        )
        await model.load()
        await model.recreate(model.prefixes)

        let report = try #require(model.report)
        #expect(report.remedy == .ownership, "a prefix the user owns was blamed on a permission")
        #expect(report.settingsPane == nil)
        #expect(
            report.message
                == "Could not write files. Check permissions, make sure your user owns the folder.")
    }

    @Test("One rebuilt prefix reports where the old one was parked")
    func rebuildOfOneReportsTheBackup() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = Recorder()
        let model = PrefixesModel(
            libraries: { [library] }, rebuild: { prefix, _ in try log.enter(prefix) })
        await model.load()
        let target = try #require(model.prefixes.first)

        await model.recreate([target])

        let backup = Recorder.backup(of: target).path(percentEncoded: false)
        #expect(model.outcome == "Rebuilt the prefix for \(target.title). The original is at "
            + "\(backup). Check that your save is present in the game, then delete the backup "
            + "to save space.")
        #expect(model.failure == nil)
    }

    @Test("A rebuild that parked nothing says nothing about a backup")
    func rebuildThatParkedNothingMentionsNoBackup() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(libraries: { [library] }, rebuild: { _, _ in nil })
        await model.load()
        let target = try #require(model.prefixes.first)

        await model.recreate([target])

        #expect(model.outcome == "Rebuilt the prefix for \(target.title).")
    }

    @Test("Backups from every prefix are listed newest first")
    func backupsAreListedNewestFirst() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try park(["1574480": ["20260101-120000"], "1649240": ["20260103-090000"]], in: library)

        let model = PrefixesModel(libraries: { [library] })
        await model.load()

        #expect(model.backups.count == 2)
        #expect(model.backups.map(\.prefix.appID) == ["1649240", "1574480"])
        #expect(model.backupBytes == model.backups.reduce(into: Int64(0)) { $0 += $1.bytes })
    }

    @Test("Deleting backups counts them rather than the prefixes")
    func deleteBackupsReportsTheCount() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try park(
            [
                "1574480": ["20260101-120000", "20260102-133000"],
                "1649240": ["20260101-120000", "20260102-133000"],
            ],
            in: library)

        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        #expect(model.backups.count == 4)

        await model.deleteBackups(model.backups)

        #expect(model.outcome == "Deleted 4 backups across 2 prefixes.")
        #expect(model.failure == nil)
        #expect(model.backups.isEmpty)
        #expect(model.prefixes.allSatisfy { PrefixStore.backups(of: $0).isEmpty })
    }

    @Test("Deleting the backups of one game names the game")
    func deleteBackupsOfOneGameNamesIt() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try park(
            ["1574480": ["20260101-120000", "20260102-133000"], "1649240": ["20260105-101500"]],
            in: library)

        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        let mine = model.backups.filter { $0.prefix.appID == "1574480" }
        #expect(mine.count == 2)

        await model.deleteBackups(mine)

        #expect(model.outcome == "Deleted 2 backups for \(mine[0].title).")
        #expect(model.backups.map(\.prefix.appID) == ["1649240"])
    }

    @Test("Deleting a single backup names the game once")
    func deleteOneBackupNamesTheGame() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try park(["1574480": ["20260101-120000"]], in: library)

        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        let only = try #require(model.backups.first)

        await model.deleteBackups([only])

        #expect(model.outcome == "Deleted the backup for \(only.title).")
        #expect(model.backups.isEmpty)
    }

    @Test("Deleting backups where there are none says nothing")
    func deleteBackupsWithNoneIsQuiet() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(libraries: { [library] })
        await model.load()

        await model.deleteBackups(model.backups)

        #expect(model.backups.isEmpty)
        #expect(model.outcome == nil)
        #expect(model.failure == nil)
    }

    private func park(_ stamps: [String: [String]], in library: SteamLibrary) throws {
        let fm = FileManager.default
        for (appID, taken) in stamps {
            for stamp in taken {
                let backup = library.compatdata.appending(path: "\(appID)/pfx.previous-\(stamp)")
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try Data("parked".utf8).write(to: backup.appending(path: "user.reg"))
            }
        }
    }

    @Test("Rebuilding nothing asks nothing of the disk")
    func rebuildOfAnEmptySelectionDoesNothing() async throws {
        let log = Recorder()
        let model = PrefixesModel(
            libraries: { [] }, rebuild: { prefix, _ in try log.enter(prefix) })
        model.outcome = "untouched"
        await model.recreate([])

        #expect(log.visited.isEmpty)
        #expect(model.outcome == "untouched")
    }

    @Test("Every selected row is busy from the start and each stops as its turn ends")
    func busyFollowsTheQueue() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240", "253750"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = Recorder(holdingEachTurn: true)
        let model = PrefixesModel(
            libraries: { [library] }, rebuild: { prefix, _ in try log.enter(prefix) })
        await model.load()
        let targets = model.prefixes

        let running = Task { await model.recreate(targets) }

        for (turn, remaining) in [(1, 3), (2, 2), (3, 1)] {
            while log.visited.count < turn { await Task.yield() }
            #expect(model.busy.count == remaining)
            log.releaseTurn()
        }
        await running.value

        #expect(model.busy.isEmpty)
    }

    @Test("A finished rebuild reads the libraries again")
    func rebuildReloadsTheList() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let box = Libraries([library])
        let log = Recorder()
        let model = PrefixesModel(
            libraries: { box.current }, rebuild: { prefix, _ in try log.enter(prefix) })
        await model.load()
        let targets = model.prefixes
        #expect(targets.count == 2)

        box.current = []
        await model.recreate(targets)

        #expect(model.prefixes.isEmpty)
    }

    @Test("Deleting takes every selected prefix")
    func deleteTakesTheWholeSelection() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "1649240", "253750"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PrefixesModel(libraries: { [library] })
        await model.load()

        let doomed = model.prefixes.filter { $0.appID != "253750" }
        model.selection = Set(doomed.map(\.id))
        #expect(model.selectedPrefixes.count == 2)

        await model.delete(model.selectedPrefixes)

        #expect(model.prefixes.map(\.appID) == ["253750"])
        #expect(model.failure == nil)
        #expect(
                model.outcome
                    == "Deleted 2 prefixes. Steam will make a new prefix if a game is launched again.")
        #expect(model.busy.isEmpty)
        #expect(!model.isLoading)
    }

    @Test("Deleting one prefix says which one")
    func deleteOfOneNamesIt() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(
            """
            "AppState"
            {
            \t"name"\t\t"Agent 64: Spies Never Die"
            }
            """, to: library.steamapps.appending(path: "appmanifest_1574480.acf"))

        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        await model.delete(model.prefixes)

        #expect(model.prefixes.isEmpty)
        #expect(
            model.outcome
                == "Deleted the prefix for Agent 64: Spies Never Die. Steam will make a new prefix "
                        + "if the game is launched again.")
    }

    @Test("A prefix that refuses does not stop the others")
    func refusalDoesNotStopTheRest() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480", "253750"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        #expect(model.prefixes.count == 2)

        let busy = try #require(model.prefixes.first { $0.appID == "253750" })
        let held = try hold(busy)
        defer { held() }

        await model.delete(model.prefixes)

        #expect(model.prefixes.map(\.appID) == ["253750"])
        #expect(model.outcome?.contains("Deleted the prefix for App 1574480.") == true)
        #expect(model.failure?.contains("is running. Quit the game first.") == true)
        #expect(model.busy.isEmpty)
    }

    private func hold(_ prefix: WinePrefix) throws -> () -> Void {
        let dir = try #require(PrefixStore.serverDirectory(of: prefix))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let socket = dir.appending(path: "socket")
        try Data().write(to: socket)

        let handle = try FileHandle(forReadingFrom: socket)
        return {
            try? handle.close()
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test("Deleting nothing is not an operation")
    func deletingNothingDoesNothing() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PrefixesModel(libraries: { [library] })
        await model.load()
        model.outcome = "untouched"

        await model.delete([])

        #expect(model.prefixes.count == 1)
        #expect(model.outcome == "untouched")
        #expect(model.failure == nil)
        #expect(!model.isLoading)
    }

    @Test("A library with no prefixes leaves nothing behind")
    func emptyLibraryClearsResults() async throws {
        let (dir, library) = try makeLibrary(appIDs: ["1574480"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let (emptyDir, emptyLibrary) = try makeLibrary(appIDs: [])
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let libraries = Libraries([library])
        let model = PrefixesModel(libraries: { libraries.current })
        await model.load()
        #expect(!model.usage.isEmpty)

        libraries.current = [emptyLibrary]
        await model.load()

        #expect(model.prefixes.isEmpty)
        #expect(model.usage.isEmpty)
        #expect(!model.isLoading)
    }
}
