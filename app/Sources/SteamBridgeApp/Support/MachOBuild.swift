import Foundation

enum MachOBuild {
    private static let fat32: UInt32 = 0xcafe_babe
    private static let fat64: UInt32 = 0xcafe_babf
    private static let thin64: UInt32 = 0xfeed_facf
    private static let thin32: UInt32 = 0xfeed_face
    private static let swapped64: UInt32 = 0xcffa_edfe
    private static let swapped32: UInt32 = 0xcefa_edfe
    private static let uuidCommand: UInt32 = 0x1b

    static func identity(of url: URL) -> [String]? {
        guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var found: Set<String> = []
        collect(bytes, at: 0, into: &found)
        return found.isEmpty ? nil : found.sorted()
    }

    private static func collect(_ bytes: Data, at offset: Int, into found: inout Set<String>) {
        guard let magic = read(bytes, at: offset, bigEndian: false) else { return }
        let fat = magic.byteSwapped

        if fat == fat32 || fat == fat64 {
            guard let count = read(bytes, at: offset + 4, bigEndian: true) else { return }
            let wide = fat == fat64
            for index in 0..<Int(count) {
                let entry = offset + 8 + index * (wide ? 32 : 20)
                guard let slice = read(bytes, at: entry + (wide ? 12 : 8), bigEndian: true) else {
                    return
                }
                readCommands(bytes, at: Int(slice), into: &found)
            }
            return
        }

        readCommands(bytes, at: offset, into: &found)
    }

    private static func readCommands(_ bytes: Data, at offset: Int, into found: inout Set<String>) {
        guard let magic = read(bytes, at: offset, bigEndian: false) else { return }
        guard [thin64, thin32, swapped64, swapped32].contains(magic) else { return }

        let flipped = magic == swapped64 || magic == swapped32
        let wide = magic == thin64 || magic == swapped64
        guard let count = read(bytes, at: offset + 16, bigEndian: flipped) else { return }

        var cursor = offset + (wide ? 32 : 28)
        for _ in 0..<Int(count) {
            guard let command = read(bytes, at: cursor, bigEndian: flipped),
                let size = read(bytes, at: cursor + 4, bigEndian: flipped), size >= 8
            else { return }

            if command == uuidCommand, let value = readUUID(bytes, at: cursor + 8) {
                found.insert(value)
            }
            cursor += Int(size)
        }
    }

    private static func read(_ bytes: Data, at offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let value = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return bigEndian ? value.bigEndian : value.littleEndian
    }

    private static func readUUID(_ bytes: Data, at offset: Int) -> String? {
        guard offset >= 0, offset + 16 <= bytes.count else { return nil }
        let raw = bytes.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: uuid_t.self)
        }
        return UUID(uuid: raw).uuidString
    }
}
