import Darwin
import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Toggle agreement")
struct ToggleAgreementTests {

    private static func source(_ path: String) throws -> String {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repo.appending(path: path), encoding: .utf8)
    }

    static func toggleNames(in webpatch: String) throws -> Set<String> {
        var names: Set<String> = []
        for pattern in [
            #"g\(\\"([A-Z0-9_]+)\\"\)"#,
            #"T\(\[\\"([A-Z0-9_]+)\\""#,
            #"\[\\"([A-Z0-9_]+)\\","#,
        ] {
            for match in webpatch.matches(of: try Regex(pattern)) {
                names.insert(String(match[1].substring ?? ""))
            }
        }
        return names
    }

    static func allowedPatterns(in compat: String) throws -> [String] {
        let line = try #require(
            compat.split(separator: "\n").first { $0.contains("*=*|") },
            "compat_run.sh no longer has a launch option allowlist")
        return line.matches(of: try Regex(#"([A-Z0-9_]+\*?=\*)"#))
            .map { String($0[1].substring ?? "") }
    }

    @Test("Every Compatibility page toggle is exported rather than passed to the game")
    func togglesAreNamespaced() throws {
        let names = try Self.toggleNames(in: try Self.source("dylib/feats/webpatch.c"))
        let patterns = try Self.allowedPatterns(in: try Self.source("dylib/feats/compat_run.sh"))

        #expect(names.count >= 8, "found \(names.count) toggles, the parse looks wrong")
        #expect(!patterns.isEmpty)

        for name in names.sorted() {
            let token = "\(name)=1"
            let covered = patterns.contains { fnmatch($0, token, 0) == 0 }
            #expect(covered, "\(name) matches no allowlist pattern in compat_run.sh, so it reads as unset")
        }
    }
}
