import Foundation
import Testing

@testable import SteamBridgeApp

@Suite("Shim agreement")
struct ShimAgreementTests {

    private static func runScript() throws -> String {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
    }

    private static func verifyRunnerBlock() throws -> String {
        let script = try runScript()
        let start = try #require(script.range(of: "verify_runner() {"))
        let rest = script[start.upperBound...]
        let end = try #require(rest.range(of: "\n}\n"))
        return String(rest[..<end.lowerBound])
    }

    private static func archLists(in block: String) -> [Set<String>] {
        block.split(separator: "\n").compactMap { line in
            guard let marker = line.range(of: "for arch in ") else { return nil }
            let tail = line[marker.upperBound...]
            guard let semicolon = tail.firstIndex(of: ";") else { return nil }
            return Set(tail[..<semicolon].split(separator: " ").map(String.init))
        }
    }

    @Test("The shim checks the ntdll arches the app patches")
    func ntdllArchesAgree() throws {
        let lists = Self.archLists(in: try Self.verifyRunnerBlock())
        #expect(lists.count == 2)
        #expect(lists.first == Set(WineArch.allCases.map(\.rawValue)))
    }

    @Test("The shim checks the builtins the app installs")
    func builtinsAgree() throws {
        let block = try Self.verifyRunnerBlock()
        let lists = Self.archLists(in: block)

        #expect(lists.count == 2)

        let arches = try #require(lists.last)
        let unix = "\"${wine_unix##*/}\""
        #expect(arches.contains(unix))
        #expect(arches.subtracting([unix]) == Set(RunnerPatcher.windowsBuiltins.map(\.arch)))

        for builtin in RunnerPatcher.windowsBuiltins {
            #expect(block.contains(builtin.name))
        }
        #expect(block.contains("lsteamclient.so"))
    }

    @Test("The shim no longer writes into the runner")
    func shimOnlyReadsTheRunner() throws {
        let script = try Self.runScript()
        for line in script.split(separator: "\n") {
            let writes = line.contains("cp -f") || line.contains("codesign ")
            guard writes, line.contains("$CX_ROOT") else { continue }
            Issue.record("RUN_SCRIPT writes into the runner: \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
}
