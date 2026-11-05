import Foundation
import Testing

@testable import SteamBridgeApp

@MainActor
@Suite("Run activity")
struct RunActivityTests {

    @Test("A run reports its progress")
    func reportsProgress() {
        let status = SystemStatus()
        let run = status.beginRun("cloning")

        status.report(run, "staging")

        #expect(status.activity == "staging")
        #expect(status.isBusy)
    }

    @Test("Nothing may start while a refresh or a run is in flight")
    func idleCoversBothKindsOfWork() {
        let status = SystemStatus()
        #expect(status.isIdle)

        status.isRefreshing = true
        #expect(!status.isIdle)

        status.isRefreshing = false
        let run = status.beginRun("cloning")
        #expect(!status.isIdle)

        status.report(run, "staging")
        #expect(!status.isIdle)

        status.endRun()
        #expect(status.isIdle)
    }

    @Test("A confirmation is remembered until it is answered")
    func pendingConfirmationSurvivesUntilCleared() {
        let status = SystemStatus()
        #expect(status.pendingConfirmation == nil)

        status.pendingConfirmation = .blockUpdates
        #expect(status.pendingConfirmation == .blockUpdates)

        status.pendingConfirmation = .replaceSteam
        #expect(status.pendingConfirmation == .replaceSteam)

        status.pendingConfirmation = nil
        #expect(status.pendingConfirmation == nil)
    }

    @Test("A finished run is not busy")
    func finishedRunIsIdle() {
        let status = SystemStatus()
        _ = status.beginRun("cloning")

        status.endRun()

        #expect(status.activity == nil)
        #expect(!status.isBusy)
    }

    @Test("A report that arrives after its run finished is ignored")
    func lateReportCannotResurrectActivity() {
        let status = SystemStatus()
        let run = status.beginRun("cloning")

        status.endRun()
        status.report(run, "finished")

        #expect(status.activity == nil)
        #expect(!status.isBusy)
    }

    @Test("A report from an earlier run cannot disturb the run after it")
    func staleReportDoesNotDisturbTheNextRun() {
        let status = SystemStatus()
        let first = status.beginRun("cloning")
        status.endRun()

        let second = status.beginRun("checking")
        status.report(first, "staging")

        #expect(status.activity == "checking")

        status.report(second, "downloading")
        #expect(status.activity == "downloading")
    }

    @Test("Every report of a run still counts, not just the first")
    func acceptsRepeatedReports() {
        let status = SystemStatus()
        let run = status.beginRun("cloning")

        for label in ["staging", "patching", "finished"] {
            status.report(run, label)
        }

        #expect(status.activity == "finished")
    }
}

@Suite("App version")
struct AppVersionTests {

    @Test("The version is never empty")
    func versionIsNeverEmpty() {
        #expect(!AppVersion.bundled.isEmpty)
        #expect(!AppVersion.fallback.isEmpty)
    }
}

@MainActor
@Suite("Failure remedies")
struct FailureRemedyTests {

    private func bundle(named name: String = "Inner") throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-remedy-\(UUID().uuidString)")
        let app = root.appending(path: name)
        try FileManager.default.createDirectory(
            at: app.appending(path: "Contents"), withIntermediateDirectories: true
        )
        try Data().write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    private func plainDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-remedy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "compatdata/1649240"), withIntermediateDirectories: true
        )
        return root.appending(path: "compatdata/1649240")
    }

    @Test("A refusal inside a bundle offers the settings pane")
    func insideABundleOffersThePane() throws {
        let target = try bundle().appending(path: "Contents/MacOS/steambridge.dylib")
        let status = SystemStatus()

        status.setFailure(WriteRefused(path: target.path(percentEncoded: false)))

        #expect(status.failureRemedy == .appManagement)
        #expect(status.failure?.contains("App Management") == true)
    }

    @Test("A refusal of a bundle itself offers the settings pane")
    func theBundleItselfOffersThePane() throws {
        let status = SystemStatus()

        status.setFailure(WriteRefused(path: try bundle().path(percentEncoded: false)))

        #expect(status.failureRemedy == .appManagement)
    }

    @Test("A refusal outside a bundle asks about ownership instead")
    func outsideABundleAsksAboutOwnership() throws {
        let target = try plainDirectory()
        let status = SystemStatus()

        status.setFailure(WriteRefused(path: target.path(percentEncoded: false)))

        #expect(
            status.failureRemedy == .ownership,
            "a prefix the user owns was sent to a permission that cannot write it"
        )
        #expect(status.failureRemedy?.settingsPane == nil)
        #expect(status.failure?.contains("App Management") == false)
    }

    @Test("A plain message does not offer the settings pane")
    func plainFailureOffersNothing() throws {
        let status = SystemStatus()
        status.setFailure(WriteRefused(path: try bundle().path(percentEncoded: false)))

        status.setFailure("No supported copy of CrossOver found.")

        #expect(
            status.failureRemedy == nil,
            "the button outlived the permission failure it belonged to"
        )
    }

    @Test("Clearing a failure clears its remedy")
    func clearingDropsTheRemedy() throws {
        let status = SystemStatus()
        status.setFailure(WriteRefused(path: try bundle().path(percentEncoded: false)))

        status.clearFailure()

        #expect(status.failure == nil)
        #expect(status.failureRemedy == nil)
    }

    @Test("The settings pane is a URL that names the App Management list")
    func settingsPaneParses() throws {
        let pane = try #require(Remedy.appManagement.settingsPane)

        #expect(pane.scheme == "x-apple.systempreferences")
        #expect(pane.query == "Privacy_AppBundles")
    }
}

@Suite("Failure reports")
struct FailureReportTests {

    private func bundlePath() throws -> String {
        let app = URL.temporaryDirectory.appending(path: "np-report-\(UUID().uuidString)/Steam.app")
        try FileManager.default.createDirectory(
            at: app.appending(path: "Contents"), withIntermediateDirectories: true
        )
        try Data().write(to: app.appending(path: "Contents/Info.plist"))
        return app.path(percentEncoded: false)
    }

    @Test("Nothing refused is no report at all")
    func emptyIsNil() {
        #expect(FailureReport([]) == nil)
    }

    @Test("Refusals that agree offer the remedy they agree on")
    func agreementOffersTheRemedy() throws {
        let report = try #require(
            FailureReport([
                WriteRefused(path: try bundlePath()),
                WriteRefused(path: try bundlePath()),
            ])
        )

        #expect(report.remedy == .appManagement)
    }

    @Test("Refusals that disagree offer no remedy")
    func disagreementOffersNothing() throws {
        let report = try #require(
            FailureReport([
                WriteRefused(path: try bundlePath()),
                WriteRefused(path: "/Users/nobody/compatdata/1649240"),
            ])
        )

        #expect(report.remedy == nil)
        #expect(report.settingsPane == nil)
    }

    @Test("One failure that is not a refusal withdraws the remedy")
    func anUnrelatedFailureWithdrawsIt() throws {
        let report = try #require(
            FailureReport([
                WriteRefused(path: try bundlePath()),
                StepFailure(step: "Delete prefix", detail: "Portal is running. Quit the game first."),
            ])
        )

        #expect(report.remedy == nil)
    }

    @Test("Repeated reasons are said once")
    func repeatedReasonsCollapse() throws {
        let report = try #require(
            FailureReport((1...3).map { _ in WriteRefused(path: "/Users/nobody/prefix") })
        )

        #expect(
            report.message == "Could not write files. Check permissions, make sure your user owns the folder."
        )
    }

    @Test("A path owned by another account is not blamed on App Management")
    func otherAccountBeatsAppManagement() throws {
        #expect(Remedy(forPath: "/usr/bin") == .otherAccount)
        #expect(Remedy(forPath: "/usr/bin").settingsPane == nil)
    }

    @Test("A bundle this account owns still asks for App Management")
    func ownedBundleAsksForAppManagement() throws {
        let root = URL.temporaryDirectory.appending(path: "np-remedy-\(UUID().uuidString)")
        let app = root.appending(path: "Steam.app")
        let inside = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: app.appending(path: "Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Remedy(forPath: inside.path(percentEncoded: false)) == .appManagement)
    }

    @Test("Distinct reasons are all kept")
    func distinctReasonsSurvive() throws {
        let report = try #require(
            FailureReport([
                StepFailure(step: "Delete prefix", detail: "Portal is running."),
                StepFailure(step: "Delete prefix", detail: "Half-Life is running."),
            ])
        )

        #expect(report.message.contains("Portal is running."))
        #expect(report.message.contains("Half-Life is running."))
    }
}

@MainActor
@Suite("Activation freshness")
struct ActivationFreshnessTests {

    private func scratch() -> URL {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appending(path: "np-activation-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot(
        install: CrossOverInstall?, activation: CrossOverActivation.Status?, bridge: URL
    ) -> StatusSnapshot {
        StatusSnapshot(
            steam: .steamMissing,
            steamRunning: false,
            updateBlocked: false,
            crossOver: install.map { [$0] } ?? [],
            crossOverActivation: install.flatMap { i in activation.map { [i.id: $0] } } ?? [:],
            runner: .none,
            payload: PayloadInspector.inspect(bridge: bridge)
        )
    }

    @Test("A stale verdict is not what the next action reads")
    func staleVerdictIsReplaced() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let install = CrossOverInstall(
            bundle: root.appending(path: "CrossOver.app"),
            releaseVersion: "20260821",
            support: .supported(SupportedRunners.all[0])
        )
        let status = SystemStatus()
        status.snapshot = snapshot(
            install: install,
            activation: CrossOverActivation.Status(
                activated: true, detail: "CrossOver is activated.",
                diagnostic: "valid activation in nowhere"
            ),
            bridge: root
        )

        let fresh = try #require(await status.checkActivation())

        #expect(!fresh.activated, "the cached verdict was handed back instead of a new one")
        #expect(
            status.snapshot?.crossOverActivation[install.id]?.activated == false,
            "the dialog would still report the verdict the check replaced"
        )
    }

    @Test("No usable install leaves nothing to check")
    func nothingToCheck() async {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let status = SystemStatus()
        status.snapshot = snapshot(
            install: CrossOverInstall(
                bundle: root.appending(path: "CrossOver.app"),
                releaseVersion: nil,
                support: .unreadable
            ),
            activation: nil,
            bridge: root
        )

        #expect(await status.checkActivation() == nil)
    }
}

@Suite("Activation questions")
struct ActivationQuestionTests {

    @Test("An install that would build a tool asks before going ahead unactivated")
    func unactivatedInstallAsks() {
        #expect(
            SystemStatus.activationQuestion(.install, activated: false, runner: .none)
                == .installUnactivated
        )
    }

    @Test("An install asks nothing when the tool it would skip is already set up")
    func installWithToolAsksNothing() {
        #expect(
            SystemStatus.activationQuestion(
                .install, activated: false, runner: .cloned(build: "27.0.0.40921", supported: true)
            ) == nil
        )
    }

    @Test("An activated install goes straight ahead")
    func activatedInstallProceeds() {
        #expect(SystemStatus.activationQuestion(.install, activated: true, runner: .none) == nil)
    }

    @Test("Setting up the tool asks whenever CrossOver is unactivated")
    func unactivatedToolAsks() {
        for runner in [RunnerState.none, .cloned(build: "27.0.0.40921", supported: true)] {
            #expect(
                SystemStatus.activationQuestion(.compatibilityTool, activated: false, runner: runner)
                    == .toolUnactivated
            )
        }
    }

    @Test("Setting up the tool goes straight ahead when CrossOver is activated")
    func activatedToolProceeds() {
        #expect(
            SystemStatus.activationQuestion(.compatibilityTool, activated: true, runner: .none)
                == nil
        )
    }

    @Test("An install that could not be checked is not treated as a refusal")
    func uncheckedProceeds() {
        #expect(SystemStatus.activationQuestion(.install, activated: nil, runner: .none) == nil)
        #expect(
            SystemStatus.activationQuestion(.compatibilityTool, activated: nil, runner: .none) == nil
        )
    }
}

@MainActor
@Suite("Run bookkeeping")
struct PerformTests {

    @Test("A run ends carrying what its body said")
    func outcomeComesFromTheBody() async {
        let status = SystemStatus()

        await status.perform(from: "Working") { _ in "Done." }

        #expect(status.outcome == "Done.")
        #expect(status.failure == nil)
    }

    @Test("A run with nothing to say leaves no outcome behind")
    func nothingToSayLeavesNoOutcome() async {
        let status = SystemStatus()

        await status.perform(from: "Working") { _ in "Done." }
        await status.perform(from: "Working") { _ in nil }

        #expect(status.outcome == nil)
    }

    @Test("A run drops the failure the one before it left")
    func aRunClearsTheEarlierFailure() async {
        let status = SystemStatus()
        status.setFailure("Old news.")

        await status.perform(from: "Working") { _ in "Done." }

        #expect(status.failure == nil)
        #expect(status.outcome == "Done.")
    }

    @Test("A body that throws ends the run as a failure and not as an outcome")
    func aThrownErrorIsRecorded() async {
        let status = SystemStatus()
        await status.perform(from: "Working") { _ in "Done." }

        await status.perform(from: "Working") { _ in
            throw StepFailure(step: "Staging", detail: "disk full")
        }

        #expect(status.failure?.contains("disk full") == true)
        #expect(status.outcome == nil)
    }

    @Test("The opening label is on screen before the body starts")
    func theOpeningLabelIsUpFirst() async {
        let status = SystemStatus()
        var seen: String?

        await status.perform(from: "Cloning") { _ in
            seen = status.activity
            return "Done."
        }

        #expect(seen == "Cloning")
    }

    @Test("A run counts as busy until it is over")
    func busyForTheWholeRun() async {
        let status = SystemStatus()
        var busyMidRun = false

        await status.perform(from: "Working") { progress in
            progress("Halfway")
            busyMidRun = status.isBusy
            return "Done."
        }

        #expect(busyMidRun)
        #expect(!status.isBusy)
    }
}
