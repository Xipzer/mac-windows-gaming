import Foundation

enum WineArch: String, Sendable, CaseIterable {
    case x86_64Windows = "x86_64-windows"
    case i386Windows = "i386-windows"
    case aarch64Windows = "aarch64-windows"
}

struct RunnerBuild: Sendable, Equatable, Identifiable {
    let bundleVersion: String

    let releaseVersion: String

    let flavor: String?

    let loaderSHA256: String

    let cleanNtdll: [WineArch: String]
    let patchedNtdll: [WineArch: String]

    var id: String { flavor.map { "\(bundleVersion)-\($0)" } ?? bundleVersion }

    var flavorName: String { flavor?.uppercased() ?? "Rosetta" }

    var displayVersion: String { "\(releaseVersion) \(flavorName)" }
}

enum SupportedRunners {

    static let all: [RunnerBuild] = [
        RunnerBuild(
            bundleVersion: "27.0.0.40921",
            releaseVersion: "20260821",
            flavor: nil,
            loaderSHA256: "b59d5fdccb62d425230a4e4d157c50c25b63ff586832c60cc5b12b4d6053ab80",
            cleanNtdll: [
                .x86_64Windows: "04c7200b6645decb7c2d1ba6b0195abc9af83257072558d11aa72cc067ac3377",
                .i386Windows: "94cc7c14c1e9dcf58ef501015c115f8405c73b2a65cefe31faa5d9e47f36e58b",
            ],
            patchedNtdll: [
                .x86_64Windows: "b21f4bace5a7a0cfef0f74cef9b27561f6eb3ad38daf76f36b186ca0677c2b2c",
                .i386Windows: "25bfde1f50ee96485763968ef10b9d9ad35e38214232f17ebdc009b098af44a0",
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.40921",
            releaseVersion: "20260821",
            flavor: "fex",
            loaderSHA256: "7a6ea337c9caf2217454bec9537371e5d8ca302406bbed40b65316c1a636c4ab",
            cleanNtdll: [
                .i386Windows: "09474795d6f306163cebab6429819999fcff50e07dbc4b067a90ec4f74a3a7d7",
                .aarch64Windows: "7823d71fbce6c9947163bf8b96beb299eabb02878245bcaf6759f2a22e81f071",
            ],
            patchedNtdll: [
                .i386Windows: "e799ea02418294588ee353a90b967358be316a3044ff9515b28aa1ce07e63981",
                .aarch64Windows: "560939a0f6e58314fc9d79fe6f839dce2b181f829ae58dca195fa142fcf40f39",
            ]
        ),
    ]

    static func build(loaderSHA256 hash: String) -> RunnerBuild? {
        all.first { $0.loaderSHA256 == hash }
    }

    static func build(id: String) -> RunnerBuild? {
        all.first { $0.id == id }
    }

    static func displayVersion(forID id: String) -> String {
        build(id: id)?.displayVersion ?? id
    }

    static var versionList: String {
        var seen = Set<String>()
        return all.map(\.releaseVersion)
            .filter { seen.insert($0).inserted }
            .joined(separator: ", ")
    }
}
