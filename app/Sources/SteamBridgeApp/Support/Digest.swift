import CryptoKit
import Foundation

enum Digest {

    private static let chunkSize = 1 << 20

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256IfPresent(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? sha256(of: url)
    }
}
