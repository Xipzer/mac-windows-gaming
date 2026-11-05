import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Runner allow list")
struct SupportedRunnerTests {

    @Test("Every row's pin hashes are complete for the arches it claims")
    func rowsAreComplete() {
        #expect(!SupportedRunners.all.isEmpty)

        for build in SupportedRunners.all {
            expectSHA256(build.loaderSHA256, "loader for \(build.id)")
            #expect(!build.cleanNtdll.isEmpty, "\(build.id) patches nothing")
            #expect(Set(build.cleanNtdll.keys) == Set(build.patchedNtdll.keys), "\(build.id) is lopsided")

            for (arch, clean) in build.cleanNtdll {
                let patched = build.patchedNtdll[arch]
                expectSHA256(clean, "clean \(arch.rawValue)")
                expectSHA256(patched ?? "", "patched \(arch.rawValue)")

                #expect(clean != patched)
            }
        }
    }

    @Test("Identities are unique so lookup is unambiguous")
    func identitiesAreUnique() {
        let ids = SupportedRunners.all.map(\.id)
        #expect(Set(ids).count == ids.count)

        let loaders = SupportedRunners.all.map(\.loaderSHA256)
        #expect(Set(loaders).count == loaders.count)
    }

    @Test("The first supported build keeps a bare version as its id")
    func firstBuildKeepsBareVersionID() {
        let build = SupportedRunners.all[0]
        #expect(build.flavor == nil)
        #expect(build.id == build.bundleVersion)
    }

    @Test("A build is named by its flavor as well as its version")
    func buildsAreNamedByFlavor() {
        let rosetta = try! #require(SupportedRunners.build(id: "27.0.0.40921"))
        let fex = try! #require(SupportedRunners.build(id: "27.0.0.40921-fex"))

        #expect(rosetta.bundleVersion == fex.bundleVersion)
        #expect(rosetta.releaseVersion == fex.releaseVersion)
        #expect(rosetta.displayVersion == "20260821 Rosetta")
        #expect(fex.displayVersion == "20260821 FEX")
        #expect(rosetta.displayVersion != fex.displayVersion)
    }

    @Test("An installed build is named the same way the picked one is")
    func installedBuildsReadBackTheSame() {
        for build in SupportedRunners.all {
            #expect(SupportedRunners.displayVersion(forID: build.id) == build.displayVersion)
            #expect(!SupportedRunners.displayVersion(forID: build.id).contains("-fex"))
        }

        #expect(SupportedRunners.displayVersion(forID: "26.0.1.1234") == "26.0.1.1234")
    }

    @Test("Lookup matches on an exact loader hash only")
    func lookupIsExact() {
        let build = SupportedRunners.all[0]
        #expect(SupportedRunners.build(loaderSHA256: build.loaderSHA256) != nil)
        #expect(SupportedRunners.build(loaderSHA256: String(build.loaderSHA256.dropLast())) == nil)
        #expect(SupportedRunners.build(loaderSHA256: build.loaderSHA256 + " ") == nil)
        #expect(SupportedRunners.build(id: build.id) != nil)
        #expect(SupportedRunners.build(id: build.id + " ") == nil)
    }

    private func expectSHA256(_ value: String, _ label: String) {
        #expect(value.count == 64, "\(label) is not a sha256")
        #expect(value.allSatisfy { $0.isHexDigit && !$0.isUppercase }, "\(label) is not lowercase hex")
    }
}

@Suite("Runner store")
struct RunnerStoreTests {

    @Test("The build comes out of the crossover- path component")
    func buildIdentifierParsing() {
        #expect(RunnerStore.buildIdentifier(
            inPath: "crossover-27.0.0.40921/CrossOver Preview.app/Contents/SharedSupport/CrossOver"
        ) == "27.0.0.40921")

        #expect(RunnerStore.buildIdentifier(
            inPath: "../runners/crossover-1.2.3/CrossOver Preview.app/Contents/SharedSupport/CrossOver"
        ) == "1.2.3")

        #expect(RunnerStore.buildIdentifier(inPath: "CrossOver Preview.app/Contents") == nil)
        #expect(RunnerStore.buildIdentifier(inPath: "") == nil)
    }
}

@Suite("Signature database selection")
struct SignatureSelectionTests {

    @Test("The highest numbered database wins, not the first listed")
    func picksHighestBuild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "np-signature-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["1788400362.json", "999999999.json", "1788400363.json", "notes.txt"] {
            try Data().write(to: directory.appending(path: name))
        }

        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == "1788400363.json")
    }

    @Test("An empty or absent directory reports nothing staged")
    func handlesEmptyDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "np-signature-empty-\(UUID().uuidString)")
        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == nil)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == nil)
    }
}

@Suite("Support paths")
struct SupportPathTests {

    @Test("Paths match what the dylib and the run script use")
    func pathsAreStable() {
        let support = SupportPaths.support.path(percentEncoded: false)
        #expect(support.hasSuffix("/Library/Application Support/SteamBridge"))

        #expect(SupportPaths.signatures.path(percentEncoded: false)
            .hasSuffix("/steambridge/signatures/macos.arm64"))
        #expect(SupportPaths.overlayShim.path(percentEncoded: false)
            .hasSuffix("/steambridge/overlay-shim.dylib"))
        #expect(SupportPaths.currentRunner.path(percentEncoded: false)
            .hasSuffix("/steambridge/runners/current"))
        #expect(SupportPaths.Steam.deployedDylib.path(percentEncoded: false)
            == "/Applications/Steam.app/Contents/MacOS/steambridge.dylib")
        #expect(SupportPaths.Steam.infoPlist.path(percentEncoded: false)
            == "/Applications/Steam.app/Contents/Info.plist")
    }
}
