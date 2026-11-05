import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Update block")
struct UpdateBlockTests {

    private func scratch() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "np-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writing the block writes the required copy and the best-effort one")
    func writesBothCopies() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let required = work.appending(path: "Steam/steam.cfg")
        let inner = work.appending(path: "Steam/Steam.AppBundle/Steam/Contents/MacOS/steam.cfg")
        try FileManager.default.createDirectory(
            at: inner.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let written = try UpdateBlock.write(to: [required, inner])

        #expect(written.count == 2)
        for url in [required, inner] {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text == "BootStrapperInhibitUpdateOnLaunch=enable\n")
        }
    }

    @Test("The best-effort copy is skipped when the client directory is not there")
    func skipsBestEffortWhenDirectoryAbsent() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let required = work.appending(path: "Steam/steam.cfg")
        let inner = work.appending(path: "no-client-here/steam.cfg")

        let written = try UpdateBlock.write(to: [required, inner])

        #expect(written == [required.path(percentEncoded: false)])
        #expect(!FileManager.default.fileExists(atPath: inner.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(
            atPath: inner.deletingLastPathComponent().path(percentEncoded: false)
        ), "a directory was created where the client is not installed")
    }

    @Test("Presence is decided by the required copy only")
    func presenceFollowsRequiredCopy() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let required = work.appending(path: "steam.cfg")
        let inner = work.appending(path: "inner/steam.cfg")
        #expect(UpdateBlock.isPresent(at: [required, inner]) == false)

        try UpdateBlock.write(to: [required])
        #expect(UpdateBlock.isPresent(at: [required, inner]))

        try Data("SomethingElse=1\n".utf8).write(to: required)
        #expect(UpdateBlock.isPresent(at: [required, inner]) == false)
    }

    @Test("Removing the block takes every copy it finds and ignores the rest")
    func removesEveryCopy() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let present = work.appending(path: "steam.cfg")
        let absent = work.appending(path: "inner/steam.cfg")
        try UpdateBlock.write(to: [present])

        let removed = try UpdateBlock.remove(from: [present, absent])

        #expect(removed == [present.path(percentEncoded: false)])
        #expect(!FileManager.default.fileExists(atPath: present.path(percentEncoded: false)))
        #expect(try UpdateBlock.remove(from: [present, absent]).isEmpty)
    }

    @Test("Writing over an existing block leaves one block, not two")
    func writeIsIdempotent() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let required = work.appending(path: "steam.cfg")
        try UpdateBlock.write(to: [required])
        try UpdateBlock.write(to: [required])

        let text = try String(contentsOf: required, encoding: .utf8)
        #expect(text == "BootStrapperInhibitUpdateOnLaunch=enable\n")
    }

    @Test("The key set to anything but enable is not a block")
    func disabledKeyIsNotABlock() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let cfg = work.appending(path: "steam.cfg")

        try Data("BootStrapperInhibitUpdateOnLaunch=disable\n".utf8).write(to: cfg)
        #expect(UpdateBlock.isPresent(at: [cfg]) == false)

        try Data("BootStrapperInhibitUpdateOnLaunch=enable\nBootStrapperInhibitUpdateOnLaunch=disable\n".utf8)
            .write(to: cfg)
        #expect(UpdateBlock.isPresent(at: [cfg]) == false)

        try Data("BootStrapperInhibitUpdateOnLaunch=enable\n".utf8).write(to: cfg)
        #expect(UpdateBlock.isPresent(at: [cfg]))
    }

    @Test("Blocking and unblocking leave the rest of the file alone")
    func otherSettingsSurvive() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let cfg = work.appending(path: "steam.cfg")
        try Data("BootStrapperInhibitAll=enable\nSomethingElse=1\n".utf8).write(to: cfg)

        try UpdateBlock.write(to: [cfg])
        var text = try String(contentsOf: cfg, encoding: .utf8)
        #expect(text == "BootStrapperInhibitAll=enable\nSomethingElse=1\nBootStrapperInhibitUpdateOnLaunch=enable\n")
        #expect(UpdateBlock.isPresent(at: [cfg]))

        try UpdateBlock.remove(from: [cfg])
        text = try String(contentsOf: cfg, encoding: .utf8)
        #expect(text == "BootStrapperInhibitAll=enable\nSomethingElse=1\n")
        #expect(FileManager.default.fileExists(atPath: cfg.path(percentEncoded: false)))
    }

    @Test("Blocking replaces a line that turned the block off")
    func blockingReplacesADisabledLine() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let cfg = work.appending(path: "steam.cfg")
        try Data("BootStrapperInhibitUpdateOnLaunch=disable\nOther=2\n".utf8).write(to: cfg)

        try UpdateBlock.write(to: [cfg])

        #expect(try String(contentsOf: cfg, encoding: .utf8)
            == "BootStrapperInhibitUpdateOnLaunch=enable\nOther=2\n")
    }

    @Test("A file holding nothing but the block is removed with it")
    func aFileOfOnlyTheBlockGoes() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let cfg = work.appending(path: "steam.cfg")

        try UpdateBlock.write(to: [cfg])
        let removed = try UpdateBlock.remove(from: [cfg])

        #expect(removed == [cfg.path(percentEncoded: false)])
        #expect(!FileManager.default.fileExists(atPath: cfg.path(percentEncoded: false)))
    }

    @Test("A file without the block is left as it is")
    func aFileWithoutTheBlockIsUntouched() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let cfg = work.appending(path: "steam.cfg")
        try Data("Other=2\n".utf8).write(to: cfg)

        #expect(try UpdateBlock.remove(from: [cfg]).isEmpty)
        #expect(try String(contentsOf: cfg, encoding: .utf8) == "Other=2\n")
    }

    @Test("The shipped paths are the two the client actually reads")
    func shippedPathsAreTheClientPaths() {
        let paths = UpdateBlock.paths.map { $0.path(percentEncoded: false) }

        #expect(paths.count == 2)
        #expect(paths[0].hasSuffix("/Application Support/Steam/steam.cfg"))
        #expect(paths[1].hasSuffix("/Steam.AppBundle/Steam/Contents/MacOS/steam.cfg"))
    }
}
