import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Pointing the current runner")
struct RunnerInstallerTests {

    private func makeRunners() throws -> URL {
        let runners = FileManager.default.temporaryDirectory
            .appending(path: "np-point-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: runners, withIntermediateDirectories: true)
        return runners
    }

    @Test("The link is relative and in the form the run script expects")
    func writesRelativeTarget() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        try RunnerInstaller.pointCurrent(atBuild: "27.0.0.40921", runners: runners)

        let target = try FileManager.default.destinationOfSymbolicLink(
            atPath: runners.appending(path: "current").path(percentEncoded: false)
        )
        #expect(target == "crossover-27.0.0.40921/CrossOver")
    }

    @Test("An existing link is replaced")
    func replacesExistingLink() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        try RunnerInstaller.pointCurrent(atBuild: "1.0.0.1", runners: runners)
        try RunnerInstaller.pointCurrent(atBuild: "2.0.0.2", runners: runners)

        let target = try FileManager.default.destinationOfSymbolicLink(
            atPath: runners.appending(path: "current").path(percentEncoded: false)
        )
        #expect(target.hasPrefix("crossover-2.0.0.2/"))

        #expect(!FileManager.default.fileExists(
            atPath: runners.appending(path: ".current.new").path(percentEncoded: false)
        ))
    }

    @Test("A directory in the way is reported instead of being worked around")
    func refusesDirectoryInTheWay() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        try FileManager.default.createDirectory(
            at: runners.appending(path: "current"), withIntermediateDirectories: true
        )

        #expect(throws: StepFailure.self) {
            try RunnerInstaller.pointCurrent(atBuild: "1.0.0.1", runners: runners)
        }
        #expect(!FileManager.default.fileExists(
            atPath: runners.appending(path: ".current.new").path(percentEncoded: false)
        ))
    }

    @Test("The copy lands as a payload directory inside the build directory")
    func copyLandsAsChildOfBuildDirectory() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let source = runners.appending(path: "source/CrossOver Preview.app/Contents/SharedSupport/CrossOver")
        try FileManager.default.createDirectory(
            at: source.appending(path: "lib/wine"), withIntermediateDirectories: true
        )

        let version = "27.0.0.40921"
        let target = SupportPaths.runnerRoot(forBuild: version, runners: runners)
        try RunnerInstaller.copyPayload(from: source, to: target)

        #expect(FileManager.default.fileExists(
            atPath: target.appending(path: "CrossOver/lib/wine").path(percentEncoded: false)
        ))

        #expect(RunnerInstaller.hasClone(forBuild: version, runners: runners))
    }

    private func makeSupportedInstall(
        in directory: URL, version: String = "27.0.0.40921"
    ) throws -> (CrossOverInstall, RunnerBuild) {
        let bundle = directory.appending(path: "source/CrossOver Preview.app")
        let wine = bundle.appending(path: "Contents/SharedSupport/CrossOver/lib/wine")

        for arch in WineArch.allCases {
            try FileManager.default.createDirectory(
                at: wine.appending(path: arch.rawValue), withIntermediateDirectories: true
            )
            try Data("ntdll for \(arch.rawValue)".utf8)
                .write(to: wine.appending(path: "\(arch.rawValue)/ntdll.dll"))
        }
        try FileManager.default.createDirectory(
            at: wine.appending(path: "x86_64-unix"), withIntermediateDirectories: true
        )
        try Data("wine loader".utf8).write(to: wine.appending(path: "x86_64-unix/wine"))

        func hash(_ url: URL) throws -> String {
            try #require(Digest.sha256IfPresent(url))
        }

        var clean: [WineArch: String] = [:]
        for arch in WineArch.allCases {
            clean[arch] = try hash(wine.appending(path: "\(arch.rawValue)/ntdll.dll"))
        }

        let build = RunnerBuild(
            bundleVersion: version,
            releaseVersion: "20260821",
            flavor: nil,
            loaderSHA256: try hash(wine.appending(path: "x86_64-unix/wine")),
            cleanNtdll: clean,
            patchedNtdll: [:]
        )
        let install = CrossOverInstall(
            bundle: bundle, releaseVersion: build.releaseVersion, support: .supported(build)
        )
        return (install, build)
    }

    @Test("A payload that never finished copying is replaced rather than kept")
    func partialCloneIsReplaced() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let (install, build) = try makeSupportedInstall(in: runners.appending(path: "src"))

        let stale = SupportPaths.clonedRoot(forBuild: build.id, runners: runners)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: stale.appending(path: "leftover"))
        #expect(!RunnerInstaller.hasClone(forBuild: build.id, runners: runners))

        _ = try RunnerInstaller.clone(from: install, runners: runners)

        #expect(RunnerInstaller.hasClone(forBuild: build.id, runners: runners))
        #expect(!FileManager.default.fileExists(
            atPath: stale.appending(path: "leftover").path(percentEncoded: false)
        ))
    }

    @Test("Cloning another build leaves the active link alone until setup finishes")
    func cloneDoesNotActivate() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let (first, firstBuild) = try makeSupportedInstall(
            in: runners.appending(path: "first"), version: "1.0.0.1"
        )
        let (second, _) = try makeSupportedInstall(
            in: runners.appending(path: "second"), version: "2.0.0.2"
        )

        _ = try RunnerInstaller.clone(from: first, runners: runners)
        #expect(RunnerStore.currentBuild(runners: runners) == nil)

        try RunnerInstaller.pointCurrent(atBuild: firstBuild.id, runners: runners)
        _ = try RunnerInstaller.clone(from: second, runners: runners)
        #expect(RunnerStore.currentBuild(runners: runners) == firstBuild.id)
    }

    @Test("A build directory with no payload in it is cloned again rather than trusted")
    func replacesACloneThatHasNoPayloadInIt() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let (install, build) = try makeSupportedInstall(in: runners)

        let target = SupportPaths.runnerRoot(forBuild: build.bundleVersion, runners: runners)
        try FileManager.default.createDirectory(
            at: target.appending(path: "Contents/SharedSupport/CrossOver"),
            withIntermediateDirectories: true
        )

        _ = try RunnerInstaller.clone(from: install, runners: runners)

        #expect(RunnerInstaller.hasClone(forBuild: build.bundleVersion, runners: runners))

        #expect(!FileManager.default.fileExists(
            atPath: target.appending(path: "Contents").path(percentEncoded: false)
        ))
    }

    @Test("A clone that kept its payload directory but lost its loader is refused")
    func refusesCloneThatLostItsLoader() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let (install, build) = try makeSupportedInstall(in: runners)
        _ = try RunnerInstaller.clone(from: install, runners: runners)

        let root = SupportPaths.clonedRoot(forBuild: build.bundleVersion, runners: runners)
        try FileManager.default.removeItem(at: CrossOverSource.unixLoader(inRoot: root))

        #expect(RunnerInstaller.hasClone(forBuild: build.bundleVersion, runners: runners))

        let failure = try #require(throws: StepFailure.self) {
            try RunnerInstaller.clone(from: install, runners: runners)
        }
        #expect(
            failure.detail.contains("no Wine loader"),
            "a clone with no loader in it was reported as something else"
        )
    }

    @Test("A failed recopy leaves the working clone and the current link intact")
    func keepsWorkingCloneWhenRecopyFails() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let (install, build) = try makeSupportedInstall(in: runners)
        _ = try RunnerInstaller.clone(from: install, runners: runners)
        try RunnerInstaller.pointCurrent(atBuild: build.id, runners: runners)

        let payload = SupportPaths
            .clonedRoot(forBuild: build.bundleVersion, runners: runners)
            .appending(path: "lib/wine")
        let current = runners.appending(path: "current")
        let files = FileManager.default

        #expect(files.fileExists(atPath: payload.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: current.path(percentEncoded: false)))

        try files.removeItem(at: runners.appending(path: "source"))

        #expect(throws: StepFailure.self) {
            try RunnerInstaller.clone(from: install, replacingExisting: true, runners: runners)
        }

        #expect(
            files.fileExists(atPath: payload.path(percentEncoded: false)),
            "a recopy that failed destroyed the working clone"
        )
        #expect(
            files.fileExists(atPath: current.path(percentEncoded: false)),
            "runners/current is dangling, so a launch resolves it to nothing"
        )
    }

    @Test("The state reader agrees with what was just written")
    func stateAgreesWithInstaller() throws {
        let runners = try makeRunners()
        defer { try? FileManager.default.removeItem(at: runners) }

        let version = SupportedRunners.all[0].bundleVersion
        try FileManager.default.createDirectory(
            at: runners.appending(path: "crossover-\(version)/CrossOver/lib/wine"),
            withIntermediateDirectories: true
        )
        try RunnerInstaller.pointCurrent(atBuild: version, runners: runners)

        #expect(RunnerStore.state(runners: runners, verify: { _, _ in [] })
            == .cloned(build: version, supported: true))
    }
}
