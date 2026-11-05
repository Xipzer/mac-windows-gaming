import Foundation

enum BridgePayload {
    static let step = "Copy the built bridge files"

    struct Entry: Sendable {
        let resource: String
        let bridgePaths: [String]
    }

    static let entries: [Entry] = [
        Entry(resource: "steam.exe", bridgePaths: [
            "steam.exe",
        ]),
        Entry(resource: "x86_64-windows-lsteamclient.dll", bridgePaths: [
            "lsteamclient.dll",
            "x86_64-windows/lsteamclient.dll",
        ]),
        Entry(resource: "aarch64-unix-lsteamclient.so", bridgePaths: [
            "aarch64-unix/lsteamclient.so",
        ]),
        Entry(resource: "x86_64-unix-lsteamclient.so", bridgePaths: [
            "lsteamclient.so",
            "x86_64-unix/lsteamclient.so",
        ]),
        Entry(resource: "i386-windows-lsteamclient.dll", bridgePaths: [
            "i386-windows/lsteamclient.dll",
        ]),
    ]

    struct Located: Sendable {
        let sources: [(source: URL, bridgePaths: [String])]
    }

    static func locate(root: URL? = nil) throws -> Located {
        let base: URL
        if let root {
            base = root
        } else {
            guard let payloadRoot = try? InstallPayload.root() else {
                throw StepFailure(
                    step: step,
                    detail: "SteamBridge carries no components."
                )
            }
            base = payloadRoot.appending(path: "bridge")
        }

        let files = FileManager.default
        var missing: [String] = []
        var sources: [(source: URL, bridgePaths: [String])] = []

        for entry in entries {
            let url = base.appending(path: entry.resource)
            if files.fileExists(atPath: url.path(percentEncoded: false)) {
                sources.append((source: url, bridgePaths: entry.bridgePaths))
            } else {
                missing.append(entry.resource)
            }
        }

        guard missing.isEmpty else {
            throw StepFailure(
                step: step,
                detail: "Missing components: \(missing.joined(separator: ", ")). "
                    + "Run make app-payload and build the app again."
            )
        }

        return Located(sources: sources)
    }

    struct Outcome: Sendable {
        let staged: [String]
        let unchanged: [String]
    }

    static func stage(
        located: Located,
        bridge: URL = SupportPaths.bridge
    ) throws -> Outcome {
        let files = FileManager.default
        var staged: [String] = []
        var unchanged: [String] = []

        for entry in located.sources {
            let sourceSize = try fileSize(entry.source)
            for bridgePath in entry.bridgePaths {
                let destination = bridge.appending(path: bridgePath)
                if let existing = try? fileSize(destination), existing == sourceSize {
                    unchanged.append(bridgePath)
                    continue
                }

                try files.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? files.removeItem(at: destination)
                try files.copyItem(at: entry.source, to: destination)
                staged.append(bridgePath)
            }
        }

        return Outcome(staged: staged, unchanged: unchanged)
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )
        return (attrs[.size] as? Int) ?? 0
    }
}
