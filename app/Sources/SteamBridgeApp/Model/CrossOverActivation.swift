import Foundation

enum CrossOverActivation {

    struct Status: Sendable {
        let activated: Bool
        let detail: String
        let diagnostic: String
    }

    static let defaultSearchDirs: [URL] = {
        let home = URL(filePath: NSHomeDirectory())
        return [
            home.appending(path: "Library/Preferences"),
            URL(filePath: "/Library/Preferences"),
        ]
    }()

    private static let activationBase = "com.codeweavers.CrossOver"

    static let notActivatedTitle = "CrossOver does not appear to be activated."
    static let notActivatedAdvice = "Please run CrossOver and try again."
    static var notActivated: String { "\(notActivatedTitle) \(notActivatedAdvice)" }

    static let defaultOpenssl = "/usr/bin/openssl"

    static func check(
        crossOverRoot: URL,
        searchDirs: [URL] = defaultSearchDirs,
        openssl: String = defaultOpenssl
    ) -> Status {
        let status = evaluate(
            crossOverRoot: crossOverRoot, searchDirs: searchDirs, openssl: openssl
        )
        AppLog.note("activation: \(status.diagnostic)")
        return status
    }

    private static func evaluate(
        crossOverRoot: URL,
        searchDirs: [URL],
        openssl: String
    ) -> Status {
        let keyFile = crossOverRoot.appending(
            path: "share/crossover/data/tie.pub"
        ).path(percentEncoded: false)

        guard FileManager.default.fileExists(atPath: keyFile) else {
            return Status(
                activated: false,
                detail: notActivated,
                diagnostic: "no verification key in the CrossOver bundle"
            )
        }

        var rejection: String?

        for dir in searchDirs {
            let label = dir.path(percentEncoded: false)
            let activation = dir.appending(path: "\(activationBase).license")
                .path(percentEncoded: false)

            guard FileManager.default.fileExists(atPath: activation) else { continue }

            let signatures = sidecars(in: dir)
            guard !signatures.isEmpty else {
                rejection = "the activation in \(label) has no signature beside it"
                continue
            }

            var unchecked: String?

            for signature in signatures {
                let result: CommandResult
                do {
                    result = try Shell.run(openssl, [
                        "dgst", signature.digest, "-verify", keyFile,
                        "-signature", signature.path, activation,
                    ])
                } catch {
                    return Status(
                        activated: false,
                        detail: notActivated,
                        diagnostic: "could not run \(openssl) to verify the activation"
                    )
                }

                if result.succeeded {
                    return Status(
                        activated: true,
                        detail: "CrossOver is activated.",
                        diagnostic: "valid activation in \(label)"
                    )
                }

                let trouble = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trouble.isEmpty {
                    if trouble.localizedCaseInsensitiveContains("unable to load key") {
                        return Status(
                            activated: false,
                            detail: notActivated,
                            diagnostic: "the verification key in the CrossOver bundle could not be read"
                        )
                    }
                    unchecked = "the activation in \(label) could not be checked"
                }
            }

            rejection = unchecked
                ?? "no signature beside the activation in \(label) verified against this bundle"
        }

        return Status(
            activated: false,
            detail: notActivated,
            diagnostic: rejection ?? "no CrossOver activation file found"
        )
    }

    static func requireValid(for install: CrossOverInstall) throws {
        let status = check(crossOverRoot: install.crossOverRoot)
        guard status.activated else {
            throw StepFailure(
                step: "Verify CrossOver activation",
                detail: status.detail
            )
        }
    }

    private static func sidecars(in dir: URL) -> [(path: String, digest: String)] {
        let candidates: [(path: String, digest: String)] = [
            (dir.appending(path: "\(activationBase).sha256").path(percentEncoded: false), "-sha256"),
            (dir.appending(path: "\(activationBase).sig").path(percentEncoded: false), "-sha1"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
