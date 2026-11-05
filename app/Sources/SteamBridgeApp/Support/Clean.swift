import Foundation

enum Clean {

    static let backupSuffix = "steambridge-orig"

    static func copy(of file: URL) -> URL {
        let backup = file.appendingPathExtension(backupSuffix)
        if FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) { return backup }
        return file
    }
}
