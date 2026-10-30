import Foundation
import Observation
import WatchKit
import ZeroLogCore

/// Runs a workout on the watch: plans it from the user's settings and saved
/// history, counts sets from wrist motion, records what was lifted, saves at the
/// end.
@Observable
@MainActor
final class WorkoutController {
    private(set) var plan: Workout?
    private(set) var active: ActiveWorkout?
    /// A plain-language problem to show the user, if any.
    private(set) var problem: String?

    /// A set the watch logged on its own. Shown with its reason and an Undo,
    /// never applied silently.
    private(set) var loggedAutomatically: String?
    /// A set the watch thinks it saw but will not log without one tap.
    private(set) var awaitingConfirmation: PendingSet?

    struct PendingSet: Equatable {
        let reps: Int
        let weight: Double
        let note: String
    }

    /// True when the user has not yet been asked about reading their wrist
    /// movement. The workout cannot start capture until this is answered.
    private(set) var needsMotionConsent = false
    /// Live detection numbers, for the diagnostics screen.
    private(set) var diagnostics = CaptureDiagnostics()

    private let store: HistoryStore?
    private let settings: SettingsProviding?
    /// Survives the app being killed mid-workout.
    private let inProgress: InProgressStore?
    private let consentStore: ConsentStore?
    private let sessions: DiagnosticsStore?
    private var session: WorkoutSessionController?

    /// Kept alive for the lifetime of the controller: it is the WCSession
    /// delegate, and letting it go would silently stop settings arriving.
    private let sync: WatchSettingsSync?

    init(settings: SettingsProviding? = nil) {
        self.store = try? HistoryStore.standard()
        self.inProgress = try? InProgressStore.standard()
        self.consentStore = try? ConsentStore.standard()
        self.sessions = try? DiagnosticsStore.standard()

        if let settings {
            // Tests inject a provider directly.
            self.settings = settings
            self.sync = nil
        } else {
            let sync = WatchSettingsSync()
            self.settings = sync
            self.sync = sync
        }
        replan()
        // Rebuild the plan the moment settings arrive, so the user does not have
        // to back out and return to see their gym appear. The callback lands off
        // the main actor, so the hop is explicit.
        sync?.onChange = { [weak self] in
            Task { @MainActor in self?.replan() }
        }
        sync?.start()

        // watchOS terminates apps routinely, and a gym session cannot be redone.
        // If one was interrupted today, resume it rather than silently losing it.
        if let resumed = try? inProgress?.resumable(today: Today.dateString()) {
            active = resumed
            resumeCapture(for: resumed)
        }
    }

    /// Writes the session after every change. A crash then costs one set, not
    /// the whole workout.
    private func persist() {
        guard let active else {
            inProgress?.clear()
            return
        }
        try? inProgress?.save(active)
    }

    func start() {
        guard let plan else { return }
        // Ask before reading movement, per guideline 2.5.14. The workout itself
        // is not blocked -- see grantMotionConsent.
        if consentStore?.load().needsAsking == true {
            needsMotionConsent = true
            return
        }
        let workout = ActiveWorkout(plan: plan, date: Today.dateString())
        active = workout
        persist()
        resumeCapture(for: workout)
    }

    /// Records the answer and starts the workout either way.
    ///
    /// Refusing must not block the workout: manual logging stays fully
    /// functional, which guideline 5.1.1(ii) requires of anything paid.
    func grantMotionConsent(_ granted: Bool) {
        try? consentStore?.save(MotionConsent(granted: granted))
        needsMotionConsent = false
        start()
    }

    /// True when the user agreed and capture should run.
    private var motionAllowed: Bool { consentStore?.load().allowsCapture ?? false }

    /// Starts motion capture for a workout, whether new or resumed.
    private func resumeCapture(for workout: ActiveWorkout) {
        guard motionAllowed else {
            // No consent: the workout runs, logging is by hand. Nothing is read.
            problem = "Reps aren't being counted. You can log sets by hand, or turn counting on in Settings."
            return
        }
        // The workout session is what keeps the app sampling once the wrist
        // drops; without it watchOS suspends us mid-set and the set is lost.
        let controller = WorkoutSessionController { [weak self] detected in
            self?.handle(detected)
        }
        session = controller
        controller.resetSession()
        // Every workout doubles as data collection for the tuner.
        controller.setRecording(true)
        controller.setCurrentExercise(repProfile: workout.current?.repProfile)
        Task { @MainActor in
            await controller.start()
            self.diagnostics = controller.diagnostics
            if case .failed(let message) = controller.state {
                // Automatic counting is a bonus, not a precondition. The manual
                // card still works, which Guideline 5.1.1(ii) also requires:
                // paid functionality must not depend on motion permission.
                self.problem = message
            }
        }
    }

    // MARK: Sets the watch counted by itself

    private func handle(_ detected: DetectedSet) {
        guard let active else { return }
        // Refresh the diagnostics screen whenever something is detected.
        if let live = session?.diagnostics { diagnostics = live }
        switch AutoLog.decide(detected: detected,
                              exercise: active.current,
                              suggestedWeight: active.suggestedWeight,
                              unit: active.plan.unit) {
        case .logSilently(let reps, let weight, let note):
            guard record(weight: weight, reps: reps) else { return }
            loggedAutomatically = note
            awaitingConfirmation = nil
            // A haptic so the user knows without lifting their wrist to look.
            WKInterfaceDevice.current().play(.success)

        case .askToConfirm(let reps, let weight, let note):
            awaitingConfirmation = PendingSet(reps: reps, weight: weight, note: note)
            loggedAutomatically = nil
            WKInterfaceDevice.current().play(.click)

        case .ignore:
            // Deliberately nothing. The normal card is already on screen, and a
            // number we do not trust is worse than no number at all.
            break
        }
    }

    func acceptPending() {
        guard let pending = awaitingConfirmation, pending.weight > 0 else { return }
        if record(weight: pending.weight, reps: pending.reps) {
            awaitingConfirmation = nil
        }
    }

    /// True while wrist movement is being read, so the UI can say so.
    var isCapturing: Bool { session != nil && motionAllowed }

    /// How many sets of this session have been kept for replay.
    var recordedSetCount: Int { session?.recordedSets.count ?? 0 }

    /// Plain-language capture state for the diagnostics screen.
    var captureState: String {
        if session == nil { return "not started" }
        if !motionAllowed { return "off (not allowed)" }
        return diagnostics.isCapturing ? "running" : "starting" 
    }

    func dismissCard() {
        awaitingConfirmation = nil
        loggedAutomatically = nil
    }

    /// Takes back a set the watch logged on its own, per the rule that every
    /// automatic change can be undone.
    func undoAutomaticLog() {
        guard var current = active, current.undoLastSet() else { return }
        active = current
        persist()
        loggedAutomatically = nil
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
    }

    // MARK: The manual path, which never goes away

    func confirm(weightKg: Double, reps: Int) {
        // A hand-entered count that differs from what the watch suggested is
        // the best training label we can get.
        if let suggested = awaitingConfirmation?.reps, suggested != reps {
            session?.noteCorrection(reps: reps)
        }
        _ = record(weight: weightKg, reps: reps)
        // The tap settled this set, so the motion still buffered for it must go.
        // Otherwise stillness closes the same physical set seconds later and it
        // is logged a second time.
        session?.discardInProgressSet()
        dismissCard()
    }

    @discardableResult
    private func record(weight: Double, reps: Int) -> Bool {
        guard var current = active else { return false }
        guard current.confirmSet(weight: weight, reps: reps) else { return false }
        active = current
        persist()
        // The next exercise needs its own calibration before its first set.
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
        return true
    }

    func skipExercise() {
        guard var current = active else { return }
        current.skipExercise()
        active = current
        persist()
        dismissCard()
        // Motion buffered for the abandoned exercise must not be credited to the
        // next one.
        session?.discardInProgressSet()
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
    }

    func endEarly() {
        guard var current = active else { return }
        current.endEarly()
        active = current
        persist()
        dismissCard()
        session?.requestStop()
    }

    /// Saves the finished workout (if anything was logged) and plans the next one.
    func finish() {
        guard let finished = active else { return }
        // Save the recorded windows before tearing the session down, so the
        // workout becomes replayable data for tuning.
        if let recorded = session?.recordedSets, !recorded.isEmpty {
            try? sessions?.save(recorded, date: finished.date,
                                sessionType: finished.plan.sessionType)
            sessions?.prune(keeping: 8)
        }
        session?.requestStop()
        session = nil
        var saveProblem: String?
        if finished.totalSetsLogged > 0 {
            do {
                guard let store else { throw CocoaError(.fileWriteUnknown) }
                try store.append(finished.session)
            } catch {
                saveProblem = "This workout couldn't be saved, so your next plan won't include it."
            }
        }
        active = nil
        // The session is in history now (or had nothing worth keeping), so the
        // resume file must go -- otherwise it would be offered again on launch.
        inProgress?.clear()
        dismissCard()
        replan()
        if let saveProblem { problem = saveProblem }
    }

    /// Plans from the user's OWN gym and session length.
    ///
    /// This used to pass a hardcoded sample gym containing every machine, plus a
    /// fixed 45 minutes, ignoring everything the user set up on their phone. A
    /// dumbbells-only user would have been shown barbell bench press with no hint
    /// the equipment list was invented. Showing nothing is better than showing a
    /// confident wrong plan, so an un-synced watch now says so.
    func replan() {
        do {
            let catalog = try Catalog.bundled()
            let history = try store?.load() ?? []
            switch PlanRequest.resolve(catalog: catalog,
                                       settings: settings?.currentSettings(),
                                       history: history,
                                       isWatch: true) {
            case .ready(let workout):
                plan = workout
                problem = store == nil ? "Workouts can't be saved on this watch right now." : nil
            case .needsSetup(let message):
                plan = nil
                problem = message
            }
        } catch {
            plan = nil
            problem = "Your workout history couldn't be read, so today's plan isn't ready."
        }
    }
}
