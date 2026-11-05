import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Valve package manifest")
struct ValvePackageManifestTests {

    @Test("The shipped manifest pins every Valve file to a package")
    func shippedManifestIsComplete() throws {
        let manifest = try ValvePackageManifest.bundled()

        #expect(manifest.files.count == 10)
        #expect(manifest.packages.count == 2)
        #expect(manifest.bases.count == 3)

        #expect(manifest.bases.first?.host() == "client-update.akamai.steamstatic.com")

        for package in manifest.packages {
            let sha1 = package.file.split(separator: ".").last.map(String.init) ?? ""
            #expect(sha1.count == 40, "\(package.file) does not end in a package sha1")
        }

        let bundle = try #require(manifest.bundle)
        #expect(bundle.file == "appdmg_osx.zip.984652b88a9737e3f4e77c656d9ffa67d5042c2c")
        #expect(bundle.sha256 == "8bf4ce8b4bcbc50f642988c955559f605e7a877372116e7a2b3fd1355004bedb")
        #expect(bundle.innerArchive == "SteamMacBootstrapper.tar.gz")
        #expect(bundle.bundleName == "Steam.app")

        let bundleSHA1 = bundle.file.split(separator: ".").last.map(String.init) ?? ""
        #expect(bundleSHA1.count == 40, "\(bundle.file) does not end in a package sha1")
    }

    @Test("A manifest with no bundle row parses, and repair is what reports it missing")
    func bundleRowIsOptional() throws {
        let hash = String(repeating: "a", count: 64)
        let manifest = try ValvePackageManifest.parse(
            """
            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(hash)
            file     tier0_s64.dll  win64  tier0_s64.dll  \(hash)
            """
        )

        #expect(manifest.bundle == nil)
    }

    @Test("Every valve payload entry has exactly one package row, and the reverse")
    func agreesWithThePayloadManifest() throws {
        let payload = try PayloadManifest.bundled()
        let packages = try ValvePackageManifest.bundled()

        let fromPayload = Set(payload.paths(origin: .valve))
        let fromPackages = Set(packages.files.map(\.bridgePath))

        #expect(fromPayload == fromPackages)
        #expect(fromPackages.count == packages.files.count, "a bridge path is listed twice")
    }

    @Test("A package is opened once per archive entry, not once per bridge path")
    func innerPathsAreDeduplicated() throws {
        let manifest = try ValvePackageManifest.bundled()

        let linux = manifest.files.filter { $0.package == "linux" }
        #expect(linux.count == 8)
        #expect(manifest.innerPaths(package: "linux").count == 6)
        #expect(manifest.innerPaths(package: "win64").count == 2)
    }

    @Test("Row kinds parse into their own collections")
    func parsesEachRowKind() throws {
        let manifest = try ValvePackageManifest.parse(
            """
            # a comment
              # an indented comment

            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(String(repeating: "a", count: 64))
            file     tier0_s64.dll  win64  tier0_s64.dll  \(String(repeating: "b", count: 64))
            bundle   appdmg_osx.zip.cc  \(String(repeating: "c", count: 64))  SteamMacBootstrapper.tar.gz  Steam.app
            """
        )

        #expect(manifest.bases.map(\.absoluteString) == ["https://example.invalid/client"])
        #expect(manifest.packages == [
            ValvePackage(id: "win64", file: "bins_win64.zip.aa", sha256: String(repeating: "a", count: 64)),
        ])
        #expect(manifest.files == [
            ValveFile(
                bridgePath: "tier0_s64.dll", package: "win64",
                innerPath: "tier0_s64.dll", sha256: String(repeating: "b", count: 64)
            ),
        ])
        #expect(manifest.bundle == ValveBundle(
            file: "appdmg_osx.zip.cc", sha256: String(repeating: "c", count: 64),
            innerArchive: "SteamMacBootstrapper.tar.gz", bundleName: "Steam.app"
        ))
    }

    @Test("A malformed manifest is refused rather than partly read")
    func refusesMalformed() {
        let hash = String(repeating: "a", count: 64)
        let good = """
            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(hash)
            file     tier0_s64.dll  win64  tier0_s64.dll  \(hash)
            """

        func parse(_ text: String) throws { _ = try ValvePackageManifest.parse(text) }

        #expect(throws: StepFailure.self) { try parse("nonsense one two") }
        #expect(throws: StepFailure.self) { try parse("") }
        #expect(throws: StepFailure.self) { try parse("# only comments") }

        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "https://", with: "http://")) }
        #expect(throws: StepFailure.self) { try parse("base not-a-url\n" + good) }

        #expect(throws: StepFailure.self) { try parse("base") }
        #expect(throws: StepFailure.self) { try parse("package win64 bins_win64.zip.aa") }
        #expect(throws: StepFailure.self) { try parse("file tier0_s64.dll win64 tier0_s64.dll") }
        #expect(throws: StepFailure.self) { try parse(good + " extra") }

        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: hash, with: "aa")) }
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: hash, with: hash.uppercased())) }
        #expect(throws: StepFailure.self) {
            try parse(good.replacingOccurrences(of: hash, with: String(repeating: "z", count: 64)))
        }

        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "base     https://example.invalid/client\n", with: "")) }
        #expect(throws: StepFailure.self) { try parse("base https://example.invalid/client") }
        #expect(throws: StepFailure.self) {
            try parse("base https://example.invalid/client\npackage win64 bins_win64.zip.aa \(hash)")
        }

        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "file     tier0_s64.dll  win64", with: "file     tier0_s64.dll  win66")) }

        #expect(throws: StepFailure.self) { try parse(good + "\nfile     tier0_s64.dll  win64  other.dll  \(hash)") }
        #expect(throws: StepFailure.self) { try parse(good + "\npackage  win64  other.zip.bb  \(hash)") }

        #expect(throws: StepFailure.self) {
            try parse(good + "\npackage  linux  bins_misc_ubuntu12.zip.bb  \(hash)")
        }

        let shared = good + "\nfile     copy.dll  win64  tier0_s64.dll  \(String(repeating: "b", count: 64))"
        #expect(throws: StepFailure.self) { try parse(shared) }
        #expect(throws: Never.self) {
            try parse(good + "\nfile     copy.dll  win64  tier0_s64.dll  \(hash)")
        }

        let bundleRow = "bundle   appdmg_osx.zip.cc  \(hash)  SteamMacBootstrapper.tar.gz  Steam.app"
        #expect(throws: StepFailure.self) {
            try parse(good + "\nbundle   appdmg_osx.zip.cc  \(hash)  SteamMacBootstrapper.tar.gz")
        }
        #expect(throws: StepFailure.self) {
            try parse(good + "\n" + bundleRow.replacingOccurrences(of: hash, with: "aa"))
        }
        #expect(throws: StepFailure.self) { try parse(good + "\n" + bundleRow + "\n" + bundleRow) }
        #expect(throws: Never.self) { try parse(good + "\n" + bundleRow) }
    }
}
