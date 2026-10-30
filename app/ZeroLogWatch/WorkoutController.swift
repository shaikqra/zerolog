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

    private let store: HistoryStore?
    private let settings: SettingsProviding?
    private var session: WorkoutSessionController?

    init(settings: SettingsProviding? = try? SettingsStore.standard()) {
        self.store = try? HistoryStore.standard()
        self.settings = settings
        replan()
    }

    func start() {
        guard let plan else { return }
        let workout = ActiveWorkout(plan: plan, date: Today.dateString())
        active = workout

        // The workout session is what keeps the app sampling once the wrist
        // drops; without it watchOS suspends us mid-set and the set is lost.
        let controller = WorkoutSessionController { [weak self] detected in
            self?.handle(detected)
        }
        session = controller
        controller.setCurrentExercise(repProfile: workout.current?.repProfile)
        Task { @MainActor in
            await controller.start()
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

    func dismissCard() {
        awaitingConfirmation = nil
        loggedAutomatically = nil
    }

    /// Takes back a set the watch logged on its own, per the rule that every
    /// automatic change can be undone.
    func undoAutomaticLog() {
        guard var current = active, current.undoLastSet() else { return }
        active = current
        loggedAutomatically = nil
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
    }

    // MARK: The manual path, which never goes away

    func confirm(weightKg: Double, reps: Int) {
        _ = record(weight: weightKg, reps: reps)
        dismissCard()
    }

    @discardableResult
    private func record(weight: Double, reps: Int) -> Bool {
        guard var current = active else { return false }
        guard current.confirmSet(weight: weight, reps: reps) else { return false }
        active = current
        // The next exercise needs its own calibration before its first set.
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
        return true
    }

    func skipExercise() {
        guard var current = active else { return }
        current.skipExercise()
        active = current
        dismissCard()
        session?.setCurrentExercise(repProfile: current.current?.repProfile)
    }

    func endEarly() {
        guard var current = active else { return }
        current.endEarly()
        active = current
        dismissCard()
        session?.requestStop()
    }

    /// Saves the finished workout (if anything was logged) and plans the next one.
    func finish() {
        guard let finished = active else { return }
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
    private func replan() {
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
