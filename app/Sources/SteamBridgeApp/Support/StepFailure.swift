import Foundation

struct StepFailure: LocalizedError {
    let step: String
    let detail: String

    var errorDescription: String? { "\(step): \(detail)" }
}
