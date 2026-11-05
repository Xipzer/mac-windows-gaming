import Foundation

let args = CommandLine.arguments
guard args.count == 3, let wantAppID = UInt32(args[2]) else {
    fputs("usage: appinfo <appinfo.vdf> <appid>\n", stderr)
    exit(2)
}

guard let file = FileManager.default.contents(atPath: args[1]) else {
    fputs("appinfo: cannot read \(args[1])\n", stderr)
    exit(1)
}
let bytes = [UInt8](file)

enum VDFError: Error {
    case truncated
    case unknownType(UInt8)
    case unknownMagic(UInt32)
    case badStringIndex(UInt32)
}

indirect enum Value {
    case string(String)
    case number(Int64)
    case section([String: Value])
}

struct Cursor {
    let b: [UInt8]
    var p: Int

    mutating func u8() throws -> UInt8 {
        guard p < b.count else { throw VDFError.truncated }
        defer { p += 1 }
        return b[p]
    }

    mutating func u32() throws -> UInt32 {
        guard p + 4 <= b.count else { throw VDFError.truncated }
        defer { p += 4 }
        return UInt32(b[p]) | UInt32(b[p + 1]) << 8
            | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24
    }

    mutating func u64() throws -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            guard p + i < b.count else { throw VDFError.truncated }
            v |= UInt64(b[p + i]) << (8 * UInt64(i))
        }
        p += 8
        return v
    }

    mutating func cstring() throws -> String {
        var end = p
        while end < b.count && b[end] != 0 { end += 1 }
        guard end < b.count else { throw VDFError.truncated }
        let s = String(decoding: b[p..<end], as: UTF8.self)
        p = end + 1
        return s
    }

    mutating func wcstring() throws -> String {
        var end = p
        while end + 1 < b.count && !(b[end] == 0 && b[end + 1] == 0) { end += 2 }
        guard end + 1 < b.count else { throw VDFError.truncated }
        var units: [UInt16] = []
        var i = p
        while i < end {
            units.append(UInt16(b[i]) | UInt16(b[i + 1]) << 8)
            i += 2
        }
        p = end + 2
        return String(decoding: units, as: UTF16.self)
    }

    mutating func skip(_ n: Int) throws {
        guard p + n <= b.count else { throw VDFError.truncated }
        p += n
    }
}

func readStringTable(_ b: [UInt8], at offset: Int) throws -> [String] {
    var c = Cursor(b: b, p: offset)
    let count = try c.u32()
    var out: [String] = []
    out.reserveCapacity(Int(count))
    for _ in 0..<count { out.append(try c.cstring()) }
    return out
}

func readSection(_ c: inout Cursor, _ table: [String]?) throws -> [String: Value] {
    var out: [String: Value] = [:]
    while true {
        let type = try c.u8()
        if type == 0x08 || type == 0x0b { return out }
        let key: String
        if let table = table {
            let i = try c.u32()
            guard Int(i) < table.count else { throw VDFError.badStringIndex(i) }
            key = table[Int(i)]
        } else {
            key = try c.cstring()
        }
        switch type {
        case 0x00: out[key] = .section(try readSection(&c, table))
        case 0x01: out[key] = .string(try c.cstring())
        case 0x02: out[key] = .number(Int64(Int32(bitPattern: try c.u32())))
        case 0x03: try c.skip(4)
        case 0x04: try c.skip(4)
        case 0x05: out[key] = .string(try c.wcstring())
        case 0x06: try c.skip(4)
        case 0x07: out[key] = .number(Int64(bitPattern: try c.u64()))
        case 0x0a: out[key] = .number(Int64(bitPattern: try c.u64()))
        default: throw VDFError.unknownType(type)
        }
    }
}

func findApp(_ b: [UInt8], _ appID: UInt32) throws -> [String: Value]? {
    var head = Cursor(b: b, p: 0)
    let magic = try head.u32()
    _ = try head.u32()

    var table: [String]? = nil
    var pos: Int
    var entryHeader = 60
    switch magic {
    case 0x0756_4429:
        let offset = try head.u64()
        guard offset < UInt64(b.count) else { throw VDFError.truncated }
        table = try readStringTable(b, at: Int(offset))
        pos = 16
    case 0x0756_4428:
        pos = 8
    case 0x0756_4427:
        pos = 8
        entryHeader = 40
    default:
        throw VDFError.unknownMagic(magic)
    }

    while pos + 8 <= b.count {
        var e = Cursor(b: b, p: pos)
        let id = try e.u32()
        if id == 0 { return nil }
        let size = Int(try e.u32())
        if id == appID {
            var kv = Cursor(b: b, p: pos + 8 + entryHeader)
            let root = try readSection(&kv, table)
            if case .section(let inner)? = root["appinfo"] { return inner }
            return root
        }
        guard size > 0 else { throw VDFError.truncated }
        pos = pos + 8 + size
    }
    return nil
}

do {
    guard let app = try findApp(bytes, wantAppID) else {
        fputs("appinfo: no entry for appid \(wantAppID)\n", stderr)
        exit(1)
    }
    guard case .section(let common)? = app["common"] else {
        fputs("appinfo: appid \(wantAppID) has no common section\n", stderr)
        exit(1)
    }
    for key in ["name", "icon", "clienticon", "logo"] {
        guard case .string(let v)? = common[key], !v.isEmpty else { continue }
        let flat = v.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        print("\(key)=\(flat)")
    }
} catch {
    fputs("appinfo: cannot parse \(args[1]): \(error)\n", stderr)
    exit(1)
}
