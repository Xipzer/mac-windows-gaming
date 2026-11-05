import Foundation

func atomicReplace(_ destination: URL, with data: Data, step: String) throws {
    let fm = FileManager.default
    let directory = destination.deletingLastPathComponent()
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)

    let staging = directory.appending(path: ".\(destination.lastPathComponent).new")
    try? fm.removeItem(at: staging)

    do {
        try data.write(to: staging)
    } catch {
        throw StepFailure(
            step: step,
            detail: "\(staging.path(percentEncoded: false)) could not be written. "
                + error.localizedDescription
        )
    }

    if rename(
        staging.path(percentEncoded: false), destination.path(percentEncoded: false)
    ) != 0 {
        let reason = String(cString: strerror(errno))
        try? fm.removeItem(at: staging)
        throw StepFailure(
            step: step,
            detail: "Replacing \(destination.path(percentEncoded: false)) failed. \(reason)"
        )
    }
}
