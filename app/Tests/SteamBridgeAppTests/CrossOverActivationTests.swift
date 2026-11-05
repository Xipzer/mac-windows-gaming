import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("CrossOver activation")
struct CrossOverActivationTests {

    private struct Fixture {
        let dir: URL
        let bundle: URL
        let local: URL
        let system: URL
        let key: URL

        var root: URL { SupportPaths.crossOverRoot(inBundle: bundle) }
        var publishedKey: URL { root.appending(path: "share/crossover/data/tie.pub") }
        var searchDirs: [URL] { [local, system] }

        func remove() { try? FileManager.default.removeItem(at: dir) }
    }

    private static let base = "com.codeweavers.CrossOver"

    private static let body = """
        [crossmac]
        customer=Test
        expires=2999/01/01
        [activation]
        id=test

        """

    private static func fixture(withKey: Bool = true) throws -> Fixture {
        let fm = FileManager.default
        let dir = URL.temporaryDirectory.appending(path: "np-activation-\(UUID().uuidString)")
        let fix = Fixture(
            dir: dir,
            bundle: dir.appending(path: "CrossOver.app"),
            local: dir.appending(path: "local"),
            system: dir.appending(path: "system"),
            key: dir.appending(path: "private.pem")
        )

        do {
            for made in [
                fix.publishedKey.deletingLastPathComponent(), fix.local, fix.system,
            ] {
                try fm.createDirectory(at: made, withIntermediateDirectories: true)
            }
            try generate(key: fix.key, publishing: withKey ? fix.publishedKey : nil)
        } catch {
            fix.remove()
            throw error
        }
        return fix
    }

    private static func generate(key: URL, publishing pub: URL?) throws {
        try Shell.check(
            CrossOverActivation.defaultOpenssl,
            ["genrsa", "-out", key.path(percentEncoded: false), "2048"]
        )
        guard let pub else { return }
        try Shell.check(CrossOverActivation.defaultOpenssl, [
            "rsa", "-in", key.path(percentEncoded: false),
            "-pubout", "-out", pub.path(percentEncoded: false),
        ])
    }

    @discardableResult
    private static func writeActivation(in dir: URL) throws -> URL {
        let activation = dir.appending(path: "\(base).license")
        try body.write(to: activation, atomically: true, encoding: .utf8)
        return activation
    }

    private static func sign(
        _ activation: URL, with key: URL, digest: String, sidecar: String
    ) throws {
        try Shell.check(CrossOverActivation.defaultOpenssl, [
            "dgst", digest, "-sign", key.path(percentEncoded: false),
            "-out", activation.deletingLastPathComponent()
                .appending(path: "\(base).\(sidecar)").path(percentEncoded: false),
            activation.path(percentEncoded: false),
        ])
    }

    @Test("An activation signed by the bundle's key is accepted")
    func validActivationIsAccepted() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(status.activated)
    }

    @Test("A bundle carrying no verification key is named in the diagnostic")
    func missingKeyIsNamed() throws {
        let fix = try Self.fixture(withKey: false)
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!status.activated)
        #expect(status.diagnostic == "no verification key in the CrossOver bundle")
        #expect(status.detail == CrossOverActivation.notActivated)
    }

    @Test("No activation file reads apart from an activation that fails")
    func absentActivationReadsApartFromInvalid() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }

        let absent = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!absent.activated)
        #expect(absent.diagnostic == "no CrossOver activation file found")
        #expect(absent.detail == CrossOverActivation.notActivated)

        let activation = try Self.writeActivation(in: fix.local)
        let other = fix.local.appending(path: "other.pem")
        try Self.generate(key: other, publishing: nil)
        try Self.sign(activation, with: other, digest: "-sha256", sidecar: "sha256")

        let wrong = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!wrong.activated)
        #expect(wrong.diagnostic.contains("verified against this bundle"))
        #expect(wrong.diagnostic != absent.diagnostic)
        #expect(wrong.detail == CrossOverActivation.notActivated)
    }

    @Test("An activation with no signature beside it is named as such")
    func unsignedActivationIsNamed() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        try Self.writeActivation(in: fix.local)

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!status.activated)
        #expect(status.diagnostic.contains("has no signature beside it"))
        #expect(status.detail == CrossOverActivation.notActivated)
    }

    @Test("A stale .sha256 does not condemn an activation the .sig verifies")
    func staleSidecarDoesNotCondemnTheActivation() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha1", sidecar: "sig")
        try Data(repeating: 0x41, count: 256).write(
            to: fix.local.appending(path: "\(Self.base).sha256")
        )

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(status.activated)
    }

    @Test("An activation kept only in the system directory is found")
    func systemDirectoryIsSearched() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.system)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(status.activated)
        #expect(status.diagnostic.contains(fix.system.path(percentEncoded: false)))
    }

    @Test("A missing openssl reads apart from an unactivated CrossOver in the log")
    func missingToolIsNotReportedAsUnactivated() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")

        let status = CrossOverActivation.check(
            crossOverRoot: fix.root,
            searchDirs: fix.searchDirs,
            openssl: "/usr/bin/steambridge-no-such-openssl"
        )
        #expect(!status.activated)
        #expect(status.diagnostic.contains("could not run"))
        #expect(status.diagnostic.contains("steambridge-no-such-openssl"))
        #expect(status.detail == CrossOverActivation.notActivated)
    }

    @Test("The refusal carries the reason the check found and nothing else")
    func refusalCarriesTheReason() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let install = CrossOverInstall(
            bundle: fix.bundle, releaseVersion: nil, support: .unreadable
        )

        let expected = CrossOverActivation.check(crossOverRoot: install.crossOverRoot)
        #expect(!expected.activated)

        do {
            try CrossOverActivation.requireValid(for: install)
            Issue.record("requireValid accepted a bundle whose key verifies nothing")
        } catch let failure as StepFailure {
            #expect(failure.detail == expected.detail)
        }
    }

    @Test("An unreadable verification key reads apart from an activation that fails in the log")
    func unreadableKeyReadsApartFromInvalid() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")
        try Data("not a key".utf8).write(to: fix.publishedKey)

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!status.activated)
        #expect(status.diagnostic == "the verification key in the CrossOver bundle could not be read")
        #expect(status.detail == CrossOverActivation.notActivated)
    }

    @Test("A signature openssl cannot read is not called an invalid activation")
    func unreadableSidecarIsNotCalledInvalid() throws {
        let fix = try Self.fixture()
        defer { fix.remove() }
        let activation = try Self.writeActivation(in: fix.local)
        try Self.sign(activation, with: fix.key, digest: "-sha256", sidecar: "sha256")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: fix.local.appending(path: "\(Self.base).sha256")
                .path(percentEncoded: false)
        )

        let status = CrossOverActivation.check(crossOverRoot: fix.root, searchDirs: fix.searchDirs)
        #expect(!status.activated)
        #expect(status.diagnostic.contains("could not be checked"))
        #expect(status.detail == CrossOverActivation.notActivated)
    }
}
