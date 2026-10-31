import Foundation
import Observation
import ZeroLogCore

// UserSettings now lives in ZeroLogCore, because the watch needs the identical
// definition -- see the note on that type.
extension UserSettings {
    /// Pounds on US phones, kilograms everywhere else (UK gyms use kg).
    static let fallback = UserSettings(equipment: [], minutes: 45,
                                       unit: Locale.current.measurementSystem == .us ? .lb : .kg)
}

/// The phone app's state: settings, saved history, today's plan and the workout in progress.
@Observable
final class AppModel {
    static let minuteOptions = [30, 45, 60, 75, 90]

    private(set) var catalog: Catalog?
    /// nil until the user finishes first-launch setup.
    private(set) var settings: UserSettings?
    /// Oldest first.
    private(set) var history: [Session] = []
    private(set) var plan: Workout?
    private(set) var active: ActiveWorkout?
    /// A plain-language problem to show the user, if any.
    private(set) var problem: String?
    /// When the last set was confirmed. Drives the rest timer.
    ///
    /// Stored as a Date rather than a running counter so the countdown stays
    /// correct across the app being backgrounded -- a timer that pauses when
    /// the user locks their phone is wrong exactly when they are resting.
    private(set) var lastSetLoggedAt: Date?
    /// The exercise that set belonged to, because rest length depends on it.
    private(set) var lastSetRestSeconds: Int = 0

    /// Exercises whose automatic weight change the user undid. Cleared once a workout is saved.
    private var undone: Set<String> = []

    private let store: HistoryStore?
    /// Shared with the watch target, so both devices read one format.
    private let settingsStore: SettingsStore?

    init() {
        store = try? HistoryStore.standard()
        settingsStore = try? SettingsStore.standard()
        catalog = try? Catalog.bundled()
        settings = try? settingsStore?.load()
        refresh()
    }

    func updateSettings(_ new: UserSettings) {
        settings = new
        try? settingsStore?.save(new)
        // The watch has its own container, so this is the only way the equipment
        // list and session length reach it.
        PhoneSettingsSync.shared.send(new)
        refresh()
    }

    /// Corrects a logged set and rebuilds the plan from the corrected history.
    ///
    /// Rebuilding matters as much as the edit: the engine reads history to pick
    /// the next weight, so a fix that did not refresh the plan would leave the
    /// user staring at a number derived from the mistake they just corrected.
    func editSet(at address: SetAddress, weightKg: Double, reps: Int) {
        let updated = HistoryEdit.update(history, at: address, weightKg: weightKg, reps: reps)
        guard updated != history else { return }   // refused, or nothing changed
        persist(updated)
    }

    func deleteSet(at address: SetAddress) {
        let updated = HistoryEdit.delete(history, at: address)
        guard updated != history else { return }
        persist(updated)
    }

    /// Tells the user what a delete will take with it, before it happens.
    func describeDelete(at address: SetAddress) -> String? {
        HistoryEdit.describeDelete(history, at: address,
                                   unit: settings?.unit ?? .kg)
    }

    private func persist(_ updated: [Session]) {
        do {
            try store?.replaceAll(updated)
            history = updated
            problem = nil
        } catch {
            // The file is the source of truth. Reloading rather than keeping
            // the edit in memory stops the screen showing a change that was
            // never saved.
            history = (try? store?.load()) ?? history
            problem = "Couldn't save that change. Your workout history is unchanged."
        }
        refresh()
    }

    func exercise(_ id: String) -> Exercise? {
        catalog?.exercises.first { $0.id == id }
    }

    /// Undo on a "What I changed" card: today's plan goes back to last time's weight for this exercise.
    func undoChange(_ exerciseId: String) {
        undone.insert(exerciseId)
        refresh()
    }

    func exerciseName(_ id: String) -> String {
        exercise(id)?.name ?? id
    }

    // MARK: Workout in progress

    /// Rest advice right now, or nil before the first set of a session.
    func restAdvice(now: Date = Date()) -> RestAdvice? {
        guard let since = lastSetLoggedAt else { return nil }
        return RestAdvice(suggestedSeconds: lastSetRestSeconds,
                          elapsedSeconds: Int(now.timeIntervalSince(since)))
    }

    /// What the rotation does after today. Order, not dates -- the app has
    /// never asked which days this user trains.
    var upcoming: [UpcomingSession] {
        guard let catalog else { return [] }
        return Engine.upcoming(catalog: catalog, history: history, count: 3)
    }

    var progress: ProgressSummary {
        Progress.summary(history: history, today: Today.dateString())
    }

    func start() {
        guard let plan else { return }
        active = ActiveWorkout(plan: plan, date: Today.dateString())
    }

    func confirm(weight: Double, reps: Int) {
        if let item = active?.current {
            lastSetRestSeconds = item.restSeconds
            lastSetLoggedAt = Date()
        }
        active?.confirmSet(weight: weight, reps: reps)
    }

    func skipExercise() {
        active?.skipExercise()
    }

    func endEarly() {
        active?.endEarly()
    }

    /// Saves the finished workout (if anything was logged) and plans the next one.
    /// Clears the timer so a new session does not inherit the last one's rest.
    private func clearRest() {
        lastSetLoggedAt = nil
        lastSetRestSeconds = 0
    }

    func finish() {
        clearRest()
        guard let finished = active else { return }
        var saveProblem: String?
        if finished.totalSetsLogged > 0 {
            do {
                guard let store else { throw CocoaError(.fileWriteUnknown) }
                try store.append(finished.session)
                undone = []
            } catch {
                saveProblem = "This workout couldn't be saved, so your next plan won't include it."
            }
        }
        active = nil
        refresh()
        if let saveProblem { problem = saveProblem }
    }

    // MARK: Planning

    private func refresh() {
        guard let catalog else {
            plan = nil
            problem = "The exercise list is missing. Reinstall ZeroLog to fix it."
            return
        }
        do {
            history = try store?.load() ?? []
            problem = store == nil ? "Workouts can't be saved on this phone right now." : nil
        } catch {
            history = []
            problem = "Your workout history couldn't be read, so today's plan starts fresh."
        }
        let current = settings ?? .fallback
        var next = Engine.generateWorkout(catalog: catalog, gymEquipment: current.equipment,
                                          minutes: current.minutes, history: history, unit: current.unit)
        for exerciseId in undone {
            next = Engine.undoChange(next, exerciseId: exerciseId)
        }
        plan = next
    }
}
