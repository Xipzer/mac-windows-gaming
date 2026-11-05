import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Bridge payload")
struct BridgePayloadTests {

    private func scratch() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "np-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakeResources(in work: URL) throws -> URL {
        let root = work.appending(path: "bridge")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for entry in BridgePayload.entries {
            let data = Data(repeating: UInt8(entry.resource.count % 256), count: entry.resource.count * 100)
            try data.write(to: root.appending(path: entry.resource))
        }
        return root
    }

    @Test("Locate finds all four resources when present")
    func locateFindsAll() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let root = try fakeResources(in: work)
        let located = try BridgePayload.locate(root: root)
        #expect(located.sources.count == BridgePayload.entries.count)
    }

    @Test("Locate reports missing resources rather than silently staging nothing")
    func locateReportsMissing() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let root = work.appending(path: "empty-bridge")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(throws: StepFailure.self) { try BridgePayload.locate(root: root) }
    }

    @Test("Stage writes all six bridge paths from four resources")
    func stageWritesAll() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let root = try fakeResources(in: work)
        let located = try BridgePayload.locate(root: root)
        let bridge = work.appending(path: "staged")
        let result = try BridgePayload.stage(located: located, bridge: bridge)

        let allPaths = BridgePayload.entries.flatMap(\.bridgePaths)
        #expect(result.staged.count == allPaths.count)
        #expect(result.unchanged.isEmpty)

        for path in allPaths {
            #expect(
                FileManager.default.fileExists(atPath: bridge.appending(path: path).path(percentEncoded: false)),
                "\(path) was not staged"
            )
        }
    }

    @Test("Files at the correct size are left alone on a second run")
    func skipsMatchingSize() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let root = try fakeResources(in: work)
        let located = try BridgePayload.locate(root: root)
        let bridge = work.appending(path: "staged")

        let first = try BridgePayload.stage(located: located, bridge: bridge)
        let second = try BridgePayload.stage(located: located, bridge: bridge)

        #expect(!first.staged.isEmpty)
        #expect(second.staged.isEmpty, "files were re-staged despite matching size")
        let allPaths = BridgePayload.entries.flatMap(\.bridgePaths)
        #expect(second.unchanged.count == allPaths.count)
    }

    @Test("Flat and arch copies are byte-identical")
    func duplicatesMatch() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        let root = try fakeResources(in: work)
        let located = try BridgePayload.locate(root: root)
        let bridge = work.appending(path: "staged")
        _ = try BridgePayload.stage(located: located, bridge: bridge)

        for entry in BridgePayload.entries where entry.bridgePaths.count > 1 {
            let first = try Data(contentsOf: bridge.appending(path: entry.bridgePaths[0]))
            for duplicate in entry.bridgePaths.dropFirst() {
                let other = try Data(contentsOf: bridge.appending(path: duplicate))
                #expect(first == other, "\(entry.bridgePaths[0]) and \(duplicate) differ")
            }
        }
    }

    @Test("The entry manifest covers every built path in payload.manifest")
    func coversPayloadManifest() throws {
        let manifest = try PayloadManifest.bundled()
        let builtPaths = Set(manifest.paths(origin: .built))
        let bridgePaths = Set(BridgePayload.entries.flatMap(\.bridgePaths))
        #expect(builtPaths == bridgePaths, "BridgePayload entries do not match payload.manifest built paths")
    }
}
