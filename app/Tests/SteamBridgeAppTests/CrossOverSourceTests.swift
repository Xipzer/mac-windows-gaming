import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Choosing between installed CrossOvers")
struct CrossOverSourceTests {

    private func install(
        _ name: String, _ support: CrossOverSupport,
        root: String = "/Applications", isManual: Bool = false
    ) -> CrossOverInstall {
        CrossOverInstall(
            bundle: URL(filePath: "\(root)/\(name).app"),
            releaseVersion: "20260821",
            support: support,
            isManual: isManual
        )
    }

    private func sorted(_ installs: [CrossOverInstall]) -> [CrossOverInstall] {
        installs.sorted(by: CrossOverSource.preferred)
    }

    private func picked(_ installs: [CrossOverInstall]) -> CrossOverInstall? {
        sorted(installs).first(where: \.isUsable)
    }

    @Test("A usable Preview is chosen ahead of a usable stable CrossOver")
    func prefersUsablePreview() {
        let build = SupportedRunners.build(id: "27.0.0.40921")!
        let stable = install("CrossOver", .supported(build))
        let preview = install("CrossOver Preview", .supported(build))

        #expect(picked([stable, preview])?.name == "CrossOver Preview")
        #expect(picked([preview, stable])?.name == "CrossOver Preview")
    }

    @Test("An incompatible stable is not chosen over a usable Preview")
    func skipsIncompatibleStable() {
        let build = SupportedRunners.build(id: "27.0.0.40921")!
        let stable = install("CrossOver", .unsupportedBuild("30.0.0.0"))
        let preview = install("CrossOver Preview", .supported(build))

        #expect(picked([stable, preview])?.name == "CrossOver Preview")
    }

    @Test("An unreadable Preview does not shadow a usable stable")
    func fallsBackToUsableStable() {
        let build = SupportedRunners.build(id: "27.0.0.40921")!
        let preview = install("CrossOver Preview", .unreadable)
        let stable = install("CrossOver", .supported(build))

        #expect(picked([preview, stable])?.name == "CrossOver")
    }

    @Test("With no usable install, nothing is chosen")
    func nonePickedWhenAllUnusable() {
        let stable = install("CrossOver", .unsupportedBuild("30.0.0.0"))
        let preview = install("CrossOver Preview", .unreadable)
        #expect(picked([stable, preview]) == nil)
    }

    @Test("The same build in both Applications folders resolves to the same one every sort")
    func breaksNameTieByPath() {
        let build = SupportedRunners.build(id: "27.0.0.40921")!
        let system = install("CrossOver Preview", .supported(build))
        let home = install("CrossOver Preview", .supported(build), root: "/Users/someone/Applications")

        let system_path = "/Applications/CrossOver Preview.app"
        #expect(picked([system, home])?.bundle.path(percentEncoded: false) == system_path)
        #expect(picked([home, system])?.bundle.path(percentEncoded: false) == system_path)
    }

    @Test("A bundle whose loader is not a known build is refused, not called modified")
    func unknownLoaderIsUnsupported() throws {
        let fm = FileManager.default
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "steambridge-cx-\(UUID().uuidString)")
        let bundle = dir.appending(path: "CrossOver Preview.app")
        let loader = bundle.appending(path: "Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine")
        try fm.createDirectory(at: loader.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let build = SupportedRunners.all[0]
        let version = build.releaseVersion
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleVersion": build.bundleVersion,
                "CFBundleShortVersionString": version,
            ],
            format: .xml, options: 0
        )
        try plist.write(to: bundle.appending(path: "Contents/Info.plist"))

        #expect(CrossOverSource.inspect(bundle: bundle).support == .unreadable)

        try Data("not the shipped loader".utf8).write(to: loader)
        #expect(CrossOverSource.inspect(bundle: bundle).support == .unsupportedBuild(version))
    }

    @Test("A bundle the user named is taken over one the search found")
    func prefersNamedBundle() {
        let build = SupportedRunners.build(id: "27.0.0.40921")!
        let found = install("CrossOver Preview", .supported(build))
        let named = install("CrossOver", .supported(build), root: "/Volumes/Spare", isManual: true)

        #expect(picked([found, named])?.isManual == true)
        #expect(picked([named, found])?.isManual == true)
    }
}
