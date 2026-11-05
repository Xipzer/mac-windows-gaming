import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Pinned download")
struct PinnedDownloadTests {

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        func add(_ s: String) { lock.lock(); seen.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "steambridge-pinned-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func host(_ root: URL, named: String, serving bytes: String) throws -> URL {
        let dir = root.appending(path: "host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: dir.appending(path: named))
        return dir
    }

    private func obtain(
        bases: [URL], into downloads: URL, sha256: String, file: String = "package.tar"
    ) async throws -> URL {
        try await PinnedDownload.obtain(
            file: file, sha256: sha256, bases: bases, into: downloads, step: "test"
        )
    }

    @Test("Bytes that match the pin are kept")
    func keepsMatchingBytes() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let body = "the real package"
        let serving = try host(work, named: "package.tar", serving: body)
        let downloads = work.appending(path: "downloads")

        let got = try await obtain(
            bases: [serving], into: downloads, sha256: Digest.sha256(of: Data(body.utf8))
        )

        #expect(try String(contentsOf: got, encoding: .utf8) == body)
    }

    @Test("Bytes that do not match the pin are refused and nothing is left behind")
    func refusesMismatchedBytes() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let serving = try host(work, named: "package.tar", serving: "a substituted package")
        let downloads = work.appending(path: "downloads")
        let wanted = Digest.sha256(of: Data("the real package".utf8))

        await #expect(throws: StepFailure.self) {
            _ = try await obtain(bases: [serving], into: downloads, sha256: wanted)
        }

        #expect(
            FileManager.default.fileExists(
                atPath: downloads.appending(path: "package.tar").path(percentEncoded: false)
            ) == false,
            "the rejected body was kept and would be reused as a cached download"
        )
    }

    @Test("A host serving the wrong bytes is passed over for one that does not")
    func fallsThroughToAHonestHost() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let body = "the real package"
        let liar = try host(work, named: "package.tar", serving: "a substituted package")
        let honest = try host(work, named: "package.tar", serving: body)
        let downloads = work.appending(path: "downloads")

        let got = try await obtain(
            bases: [liar, honest], into: downloads, sha256: Digest.sha256(of: Data(body.utf8))
        )

        #expect(try String(contentsOf: got, encoding: .utf8) == body)
    }

    @Test("An archive already on disk that matches is not fetched again")
    func reusesMatchingArchive() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let body = "the real package"
        let downloads = work.appending(path: "downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: downloads.appending(path: "package.tar"))

        let reported = Reports()
        let got = try await PinnedDownload.obtain(
            file: "package.tar",
            sha256: Digest.sha256(of: Data(body.utf8)),
            bases: [],
            into: downloads,
            step: "test",
            report: { reported.add($0.label) }
        )

        #expect(reported.all == ["Preparing"])
        #expect(try String(contentsOf: got, encoding: .utf8) == body)
    }

    @Test("A fetch reports the host the bytes came from")
    func reportsTheHostFetchedFrom() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let body = "the real package"
        let serving = try host(work, named: "package.tar", serving: body)
        let reported = Reports()

        _ = try await PinnedDownload.obtain(
            file: "package.tar",
            sha256: Digest.sha256(of: Data(body.utf8)),
            bases: [serving],
            into: work.appending(path: "downloads"),
            step: "test",
            report: { reported.add($0.label) }
        )

        let label = try #require(reported.all.first)
        #expect(reported.all.count == 1)
        #expect(label.hasPrefix("Downloading from "))
        #expect(label.contains(serving.lastPathComponent))
    }
}
