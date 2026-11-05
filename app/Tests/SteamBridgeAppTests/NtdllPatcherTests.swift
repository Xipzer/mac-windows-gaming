import Foundation
import Testing

@testable import SteamBridgeApp

private struct StubPE {
    static let peOffset = 0x80
    static let sectionVirtualAddress = 0x1000
    static let sectionRawOffset = 0x400
    static let sectionSize = 0x4000

    static let bssVirtualAddress = 0x200
    static let bssSize = 0x200

    static func rva(forOffset offset: Int) -> Int {
        sectionVirtualAddress + (offset - sectionRawOffset)
    }

    static func make(machine: UInt16, magic: UInt16, imageBase: UInt64) -> Data {
        var bytes = [UInt8](repeating: 0, count: sectionRawOffset + sectionSize)

        write(&bytes, 0x3c, UInt32(peOffset))
        write(&bytes, peOffset, UInt32(0x0000_4550))
        write(&bytes, peOffset + 4, machine)

        let optionalSize: UInt16 = 0xf0
        write(&bytes, peOffset + 6, UInt16(2))
        write(&bytes, peOffset + 20, optionalSize)
        write(&bytes, peOffset + 24, magic)

        if magic == 0x20b {
            write(&bytes, peOffset + 24 + 24, imageBase)
        } else {
            write(&bytes, peOffset + 24 + 28, UInt32(truncatingIfNeeded: imageBase))
        }

        let table = peOffset + 24 + Int(optionalSize)
        write(&bytes, table + 8, UInt32(bssSize))
        write(&bytes, table + 12, UInt32(bssVirtualAddress))
        write(&bytes, table + 16, UInt32(0))
        write(&bytes, table + 20, UInt32(0))

        write(&bytes, table + 40 + 8, UInt32(sectionSize))
        write(&bytes, table + 40 + 12, UInt32(sectionVirtualAddress))
        write(&bytes, table + 40 + 16, UInt32(sectionSize))
        write(&bytes, table + 40 + 20, UInt32(sectionRawOffset))

        return Data(bytes)
    }

    private static func write<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ offset: Int, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { raw in
            for (index, byte) in raw.enumerated() { bytes[offset + index] = byte }
        }
    }
}

@Suite("ntdll patcher")
struct NtdllPatcherTests {

    private let stolen: [UInt8] = [0x48, 0x83, 0xbc, 0x24, 0xf0, 0x00, 0x00, 0x00, 0x00]

    private func stubPatch(caveSize: Int = 0x100, cavePad: UInt8 = 0) -> NtdllPatch {
        NtdllPatch(
            arch: .x86_64Windows,
            payloadResource: "detour2",
            payloadSHA256: "unused",
            caveRVA: StubPE.rva(forOffset: StubPE.sectionRawOffset + 0x800),
            payloadRVA: StubPE.rva(forOffset: StubPE.sectionRawOffset + 0x800),
            hooks: [
                NtdllHook(rva: StubPE.rva(forOffset: StubPE.sectionRawOffset + 0x100), stolen: stolen)
            ],
            caveSize: caveSize,
            cavePad: cavePad,
            machine: 0x8664,
            magic: 0x20b,
            imageBase: 0x1_7000_0000
        )
    }

    private func stubImage() -> Data {
        var bytes = [UInt8](StubPE.make(machine: 0x8664, magic: 0x20b, imageBase: 0x1_7000_0000))
        let hookOffset = StubPE.sectionRawOffset + 0x100
        for (index, byte) in stolen.enumerated() { bytes[hookOffset + index] = byte }
        return Data(bytes)
    }

    @Test("A patch writes the detour into the cave and a reachable jump at the hook")
    func patchWritesBothSites() throws {
        let patch = stubPatch()
        let payload = Data([0x90, 0x91, 0x92, 0x93])
        let result = [UInt8](try NtdllPatcher.apply(patch, to: stubImage(), payload: payload))

        let caveOffset = StubPE.sectionRawOffset + 0x800
        #expect(Array(result[caveOffset ..< caveOffset + 4]) == [0x90, 0x91, 0x92, 0x93])

        let hookOffset = StubPE.sectionRawOffset + 0x100
        #expect(result[hookOffset] == 0xe9)

        let displacement = result[(hookOffset + 1) ..< (hookOffset + 5)]
            .reversed()
            .reduce(Int32(0)) { $0 << 8 | Int32($1) }
        #expect(Int(displacement) == patch.payloadRVA - (patch.hooks[0].rva + 5))

        #expect(Array(result[(hookOffset + 5) ..< (hookOffset + stolen.count)]) == [0xcc, 0xcc, 0xcc, 0xcc])
    }

    @Test("The file keeps its length, because a PE cannot absorb inserted bytes")
    func patchDoesNotResize() throws {
        let patch = stubPatch()
        let image = stubImage()
        let result = try NtdllPatcher.apply(patch, to: image, payload: Data(repeating: 0x90, count: 64))
        #expect(result.count == image.count)
    }

    @Test("A hook site holding something else is refused")
    func wrongStolenBytesRefused() throws {
        let patch = stubPatch()
        var bytes = [UInt8](stubImage())
        bytes[StubPE.sectionRawOffset + 0x100] = 0x90

        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(patch, to: Data(bytes), payload: Data([0x90]))
        }
    }

    @Test("A cave with anything in it is refused, so a second patch cannot stack")
    func occupiedCaveRefused() throws {
        let patch = stubPatch()
        let payload = Data(repeating: 0x90, count: 32)
        let once = try NtdllPatcher.apply(patch, to: stubImage(), payload: payload)

        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(patch, to: once, payload: payload)
        }
    }

    @Test("A detour larger than the cave is refused rather than overrunning it")
    func oversizePayloadRefused() throws {
        let patch = stubPatch(caveSize: 16)
        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(patch, to: stubImage(), payload: Data(repeating: 0x90, count: 17))
        }
    }

    @Test("A mismatched machine, optional header or image base is refused")
    func headerMismatchRefused() throws {
        let patch = stubPatch()
        let payload = Data([0x90])

        let wrongMachine = StubPE.make(machine: 0x14c, magic: 0x20b, imageBase: 0x1_7000_0000)
        #expect(throws: StepFailure.self) { try NtdllPatcher.apply(patch, to: wrongMachine, payload: payload) }

        let wrongMagic = StubPE.make(machine: 0x8664, magic: 0x10b, imageBase: 0x1_7000_0000)
        #expect(throws: StepFailure.self) { try NtdllPatcher.apply(patch, to: wrongMagic, payload: payload) }

        let wrongBase = StubPE.make(machine: 0x8664, magic: 0x20b, imageBase: 0x1_8000_0000)
        #expect(throws: StepFailure.self) { try NtdllPatcher.apply(patch, to: wrongBase, payload: payload) }
    }

    @Test("A truncated file is refused instead of read past its end")
    func truncatedFileRefused() throws {
        let patch = stubPatch()
        let image = stubImage().prefix(StubPE.sectionRawOffset)

        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(patch, to: Data(image), payload: Data([0x90]))
        }
    }

    @Test("A detour addressed below its cave is refused")
    func detourBelowItsCaveRefused() throws {
        let base = stubPatch()
        let below = NtdllPatch(
            arch: base.arch, payloadResource: base.payloadResource, payloadSHA256: base.payloadSHA256,
            caveRVA: base.caveRVA, payloadRVA: base.caveRVA - 0x100, hooks: base.hooks,
            caveSize: base.caveSize, cavePad: base.cavePad, machine: base.machine,
            magic: base.magic, imageBase: base.imageBase
        )

        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(below, to: stubImage(), payload: Data(repeating: 0x90, count: 0x10))
        }
    }

    @Test("An RVA in no mapped section is refused, including one inside an unbacked section")
    func unmappedRVARefused() throws {
        let base = stubPatch()
        let payload = Data([0x90])

        let beyond = NtdllPatch(
            arch: base.arch, payloadResource: base.payloadResource, payloadSHA256: base.payloadSHA256,
            caveRVA: 0x9000_0000, payloadRVA: 0x9000_0000, hooks: base.hooks, caveSize: base.caveSize,
            cavePad: base.cavePad, machine: base.machine, magic: base.magic, imageBase: base.imageBase
        )
        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(beyond, to: stubImage(), payload: payload)
        }

        let unbacked = NtdllPatch(
            arch: base.arch, payloadResource: base.payloadResource, payloadSHA256: base.payloadSHA256,
            caveRVA: StubPE.bssVirtualAddress + 0x10, payloadRVA: StubPE.bssVirtualAddress + 0x10,
            hooks: base.hooks,
            caveSize: base.caveSize, cavePad: base.cavePad, machine: base.machine, magic: base.magic,
            imageBase: base.imageBase
        )
        #expect(throws: StepFailure.self) {
            try NtdllPatcher.apply(unbacked, to: stubImage(), payload: payload)
        }
    }

    @Test("Both detour payloads ship and match the hashes they were built with")
    func shippedPayloadsMatch() throws {
        for build in SupportedRunners.all {
            for patch in NtdllPatcher.patches(for: build) {
                let payload = try NtdllPatcher.payload(for: patch)
                #expect(!payload.isEmpty)
                #expect(Digest.sha256(of: payload) == patch.payloadSHA256)
            }
        }
    }

    @Test("Every build's patches line up with the arches it records hashes for")
    func patchesMatchRecordedArches() {
        for build in SupportedRunners.all {
            let patched = Set(NtdllPatcher.patches(for: build).map(\.arch))
            #expect(patched == Set(build.cleanNtdll.keys))
            #expect(patched == Set(build.patchedNtdll.keys))
            for arch in patched {
                #expect(NtdllPatcher.patch(for: arch, in: build) != nil)
            }
        }
        #expect(!NtdllPatcher.patches(for: SupportedRunners.all[0]).isEmpty)
    }

    @Test("Patching the unpatched ntdll reproduces the recorded hashes")
    func realNtdllReproducesRecordedHashes() throws {
        let root = URL(filePath: "/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver")
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
              let installed = Digest.sha256IfPresent(CrossOverSource.unixLoader(inRoot: root)),
              let build = SupportedRunners.build(loaderSHA256: installed)
        else { return }

        var reproduced: [WineArch] = []
        for patch in NtdllPatcher.patches(for: build) {
            let source = NtdllPatcher.cleanSource(inRoot: root, arch: patch.arch)
            guard let hash = Digest.sha256IfPresent(source), hash == build.cleanNtdll[patch.arch] else {
                continue
            }

            let patched = try NtdllPatcher.apply(
                patch, to: try Data(contentsOf: source), payload: try NtdllPatcher.payload(for: patch)
            )
            #expect(Digest.sha256(of: patched) == build.patchedNtdll[patch.arch])
            reproduced.append(patch.arch)
        }

        #expect(reproduced.count == build.cleanNtdll.count)
    }

    @Test("An input that is not the pinned build is refused before anything is written")
    func unpinnedInputRefused() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appending(path: "ntdll.dll")
        try Data(repeating: 0, count: 1024).write(to: source)

        var checked = 0
        for build in SupportedRunners.all {
            for patch in NtdllPatcher.patches(for: build) {
                let destination = directory.appending(path: "out-\(build.id)-\(patch.arch.rawValue).dll")
                #expect(throws: StepFailure.self) {
                    try NtdllPatcher.write(patch, build: build, from: source, to: destination)
                }
                #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test("A missing input is refused by name")
    func missingInputRefused() throws {
        let source = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-absent-\(UUID().uuidString)")

        var checked = 0
        for build in SupportedRunners.all {
            for patch in NtdllPatcher.patches(for: build) {
                #expect(throws: StepFailure.self) {
                    try NtdllPatcher.write(patch, build: build, from: source, to: source)
                }
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    private static func cleanRunnerRoot(for build: RunnerBuild) -> URL? {
        let root = SupportPaths.currentRunner
        guard FileManager.default.fileExists(
            atPath: root.appending(path: "lib/wine").path(percentEncoded: false)
        ) else { return nil }

        for patch in NtdllPatcher.patches(for: build) {
            let source = NtdllPatcher.cleanSource(inRoot: root, arch: patch.arch)
            guard Digest.sha256IfPresent(source) == build.cleanNtdll[patch.arch] else {
                return nil
            }
        }
        return root
    }

    @Test("Staging reproduces the bridge the python patcher produced")
    func stagingReproducesExistingBridge() throws {
        for build in SupportedRunners.all {
            guard let root = Self.cleanRunnerRoot(for: build) else { continue }
            try Self.expectStagingReproducesBridge(build: build, root: root)
        }
    }

    private static func expectStagingReproducesBridge(build: RunnerBuild, root: URL) throws {
        let fm = FileManager.default

        let scratch = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-stage-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }

        try NtdllPatcher.stage(build: build, runnerRoot: root, bridge: scratch)

        var compared: [WineArch] = []
        for patch in NtdllPatcher.patches(for: build) {
            let relative = "wine/\(patch.arch.rawValue)/ntdll.dll"
            let staged = scratch.appending(path: relative)
            let existing = SupportPaths.bridge.appending(path: relative)

            #expect(Digest.sha256IfPresent(staged) == build.patchedNtdll[patch.arch])
            guard let live = Digest.sha256IfPresent(existing) else { continue }
            #expect(Digest.sha256IfPresent(staged) == live)
            compared.append(patch.arch)
        }

        let bridgeHoldsThisBuild = build.patchedNtdll.keys.contains { arch in
            Digest.sha256IfPresent(SupportPaths.bridge.appending(path: "wine/\(arch.rawValue)/ntdll.dll")) != nil
        }
        if bridgeHoldsThisBuild {
            #expect(compared.count == build.patchedNtdll.count)
        }
    }

    @Test("Staging a second time writes nothing, so it is safe on every install")
    func stagingIsIdempotent() throws {
        for build in SupportedRunners.all {
            guard let root = Self.cleanRunnerRoot(for: build) else { continue }
            let fm = FileManager.default

            let scratch = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-stage-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: scratch) }

            let first = try NtdllPatcher.stage(build: build, runnerRoot: root, bridge: scratch)
            #expect(first.count == NtdllPatcher.patches(for: build).count)

            let second = try NtdllPatcher.stage(build: build, runnerRoot: root, bridge: scratch)
            #expect(second.isEmpty)
        }
    }

    @Test("The clean source prefers the one time backup over a live file")
    func cleanSourcePrefersBackup() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-root-\(UUID().uuidString)")
        let directory = root.appending(path: "lib/wine/x86_64-windows")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let live = directory.appending(path: "ntdll.dll")
        try Data([0x00]).write(to: live)
        #expect(NtdllPatcher.cleanSource(inRoot: root, arch: .x86_64Windows) == live)

        let backup = directory.appending(path: "ntdll.dll.steambridge-orig")
        try Data([0x00]).write(to: backup)
        #expect(NtdllPatcher.cleanSource(inRoot: root, arch: .x86_64Windows) == backup)
    }
}

@Suite("ntdll staging")
struct NtdllStagingTests {

    private func stagedBridge() throws -> (bridge: URL, build: RunnerBuild) {
        let bridge = FileManager.default.temporaryDirectory
            .appending(path: "np-bridge-\(UUID().uuidString)")

        var hashes: [WineArch: String] = [:]
        for arch in WineArch.allCases {
            let directory = bridge.appending(path: "wine/\(arch.rawValue)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: "ntdll.dll")
            try Data("staged \(arch.rawValue)".utf8).write(to: file)
            hashes[arch] = try Digest.sha256(of: file)
        }

        let build = RunnerBuild(
            bundleVersion: "27.0.0.40921",
            releaseVersion: "20260821",
            flavor: "fex",
            loaderSHA256: "unused",
            cleanNtdll: [:],
            patchedNtdll: [
                .i386Windows: hashes[.i386Windows]!,
                .aarch64Windows: hashes[.aarch64Windows]!,
            ]
        )
        return (bridge, build)
    }

    @Test("Staging drops an ntdll left in the bridge for an arch this build does not patch")
    func stagingPrunesForeignArches() throws {
        let (bridge, build) = try stagedBridge()
        defer { try? FileManager.default.removeItem(at: bridge) }

        let written = try NtdllPatcher.stage(
            build: build, runnerRoot: bridge.appending(path: "unused"), bridge: bridge
        )
        #expect(written.isEmpty)

        let fm = FileManager.default
        for arch in [WineArch.i386Windows, .aarch64Windows] {
            let kept = bridge.appending(path: "wine/\(arch.rawValue)/ntdll.dll")
            #expect(fm.fileExists(atPath: kept.path(percentEncoded: false)))
        }

        let foreign = bridge.appending(path: "wine/x86_64-windows/ntdll.dll")
        #expect(!fm.fileExists(atPath: foreign.path(percentEncoded: false)))
    }
}
