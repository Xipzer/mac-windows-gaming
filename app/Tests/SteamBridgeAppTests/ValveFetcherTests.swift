import Foundation
import Testing

@testable import SteamBridgeApp

private final class PhaseLog: @unchecked Sendable {
    var labels: [String] = []
}

@Suite("Valve fetcher", .serialized)
struct ValveFetcherTests {

    private func scratchBridge() throws -> URL {
        let bridge = FileManager.default.temporaryDirectory
            .appending(path: "np-valve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true)
        return bridge
    }

    @Test("An empty bridge gets all ten files, each matching its pin")
    func fillsAnEmptyBridge() async throws {
        let bridge = try scratchBridge()
        defer { try? FileManager.default.removeItem(at: bridge) }

        let manifest = try ValvePackageManifest.bundled()
        let log = PhaseLog()
        let outcome = try await ValveFetcher.run(manifest: manifest, bridge: bridge) { phase in
            log.labels.append(phase.label)
        }
        let phases = log.labels

        #expect(outcome.installed.count == 10)
        #expect(outcome.unchanged.isEmpty)
        #expect(!outcome.wroteNothing)

        for file in manifest.files {
            let landed = Digest.sha256IfPresent(bridge.appending(path: file.bridgePath))
            #expect(landed == file.sha256, "\(file.bridgePath) landed as \(landed ?? "nothing")")
        }

        #expect(phases.contains(ValveFetcher.Phase.verifying.label))
        #expect(phases.contains(ValveFetcher.Phase.installing.label))
        #expect(phases.last == ValveFetcher.Phase.finished.label)
        #expect(phases.filter { $0 == "Extracting" }.count == manifest.packages.count)
    }

    @Test("The download phase shows the download's own wording")
    func downloadPhaseDelegatesItsLabel() {
        #expect(ValveFetcher.Phase.downloading(.reusing).label
                == PinnedDownload.Progress.reusing.label)
        #expect(ValveFetcher.Phase.downloading(.fetching(host: "cdn.example")).label
                == "Downloading from cdn.example")
    }

    @Test("A bridge that is already correct is left alone")
    func secondRunWritesNothing() async throws {
        let bridge = try scratchBridge()
        defer { try? FileManager.default.removeItem(at: bridge) }

        let manifest = try ValvePackageManifest.bundled()
        _ = try await ValveFetcher.run(manifest: manifest, bridge: bridge)
        let again = try await ValveFetcher.run(manifest: manifest, bridge: bridge)

        #expect(again.installed.isEmpty)
        #expect(again.unchanged.count == 10)
        #expect(again.wroteNothing)
    }

    @Test("A file that is missing or wrong is replaced, and the rest are not touched")
    func repairsOnlyWhatIsWrong() async throws {
        let bridge = try scratchBridge()
        defer { try? FileManager.default.removeItem(at: bridge) }

        let manifest = try ValvePackageManifest.bundled()
        _ = try await ValveFetcher.run(manifest: manifest, bridge: bridge)

        let deleted = "tier0_s64.dll"
        let corrupted = "legacycompat/steamclient64.dll"
        try FileManager.default.removeItem(at: bridge.appending(path: deleted))
        try Data("not a PE".utf8).write(to: bridge.appending(path: corrupted))

        let repair = try await ValveFetcher.run(manifest: manifest, bridge: bridge)

        #expect(Set(repair.installed) == [deleted, corrupted])
        #expect(repair.unchanged.count == 8)
        for path in [deleted, corrupted] {
            let want = manifest.files.first { $0.bridgePath == path }?.sha256
            #expect(Digest.sha256IfPresent(bridge.appending(path: path)) == want)
        }
    }

    @Test("A file whose extracted bytes do not match its pin stops the whole install")
    func refusesAFileThatFailsItsPin() async throws {
        let bridge = try scratchBridge()
        defer { try? FileManager.default.removeItem(at: bridge) }

        let real = try ValvePackageManifest.bundled()
        let tampered = ValvePackageManifest(
            bases: real.bases,
            packages: real.packages,
            files: real.files.map { file in
                file.bridgePath == "tier0_s64.dll"
                    ? ValveFile(
                        bridgePath: file.bridgePath, package: file.package,
                        innerPath: file.innerPath, sha256: String(repeating: "0", count: 64)
                    )
                    : file
            },
            bundle: real.bundle
        )

        await #expect(throws: StepFailure.self) {
            try await ValveFetcher.run(manifest: tampered, bridge: bridge)
        }

        let landed = try FileManager.default.contentsOfDirectory(atPath: bridge.path(percentEncoded: false))
        #expect(landed.isEmpty, "the bridge got \(landed) from a run that failed verification")
    }

    @Test("A copy that fails part way leaves the previous binary in place")
    func keepsPreviousBinaryWhenACopyFails() throws {
        let bridge = try scratchBridge()
        let extracted = try scratchBridge()
        defer {
            try? FileManager.default.removeItem(at: bridge)
            try? FileManager.default.removeItem(at: extracted)
        }

        let files = FileManager.default
        try Data("new first".utf8).write(to: extracted.appending(path: "first.dll"))
        try Data("new second".utf8).write(to: extracted.appending(path: "second.dll"))

        func pin(_ name: String) throws -> String {
            try #require(Digest.sha256IfPresent(extracted.appending(path: name)))
        }

        let manifest = ValvePackageManifest(
            bases: [URL(string: "https://example.com")!],
            packages: [
                ValvePackage(id: "bins", file: "bins.zip", sha256: String(repeating: "a", count: 64))
            ],
            files: [
                ValveFile(
                    bridgePath: "first.dll", package: "bins",
                    innerPath: "first.dll", sha256: try pin("first.dll")
                ),
                ValveFile(
                    bridgePath: "second.dll", package: "bins",
                    innerPath: "second.dll", sha256: try pin("second.dll")
                ),
            ],
            bundle: nil
        )

        try Data("old first".utf8).write(to: bridge.appending(path: "first.dll"))
        try Data("old second".utf8).write(to: bridge.appending(path: "second.dll"))

        try files.removeItem(at: extracted.appending(path: "second.dll"))

        #expect(throws: (any Error).self) {
            try ValveFetcher.install(manifest, from: extracted, into: bridge)
        }

        let first = try? String(contentsOf: bridge.appending(path: "first.dll"), encoding: .utf8)
        #expect(first == "new first", "the loop never got as far as the first copy")

        let second = try? String(contentsOf: bridge.appending(path: "second.dll"), encoding: .utf8)
        #expect(
            second == "old second",
            "a copy that failed removed the previous binary, leaving \(second ?? "nothing")"
        )

        let landed = try files.contentsOfDirectory(atPath: bridge.path(percentEncoded: false))
        #expect(
            !landed.contains { $0.contains("steambridge-pending") },
            "a staging file was left in the bridge: \(landed)"
        )
    }

    @Test("A package whose bytes do not match its pin is refused, and nothing is installed")
    func refusesAPackageThatFailsItsPin() async throws {
        let bridge = try scratchBridge()
        let downloads = try scratchBridge()
        defer {
            try? FileManager.default.removeItem(at: bridge)
            try? FileManager.default.removeItem(at: downloads)
        }

        let real = try ValvePackageManifest.bundled()
        let decoy = ValvePackageManifest(
            bases: [URL(string: "https://example.com")!],
            packages: real.packages,
            files: real.files,
            bundle: real.bundle
        )

        await #expect(throws: StepFailure.self) {
            try await ValveFetcher.run(manifest: decoy, bridge: bridge, downloads: downloads)
        }

        let landed = try FileManager.default.contentsOfDirectory(atPath: bridge.path(percentEncoded: false))
        #expect(landed.isEmpty, "the bridge got \(landed) from a package that failed its pin")
    }
}
