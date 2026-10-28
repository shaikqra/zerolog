import Foundation
import Observation
import ZeroLogCore

/// Runs a workout on the watch: plans it from saved history, records each confirmed set, saves at the end.
@Observable
final class WorkoutController {
    private(set) var plan: Workout?
    private(set) var active: ActiveWorkout?
    /// A plain-language problem to show the user, if any.
    private(set) var problem: String?
    private let store: HistoryStore?

    init() {
        store = try? HistoryStore.standard()
        replan()
    }

    func start() {
        guard let plan else { return }
        active = ActiveWorkout(plan: plan, date: Today.dateString())
    }

    func confirm(weightKg: Double, reps: Int) {
        active?.confirmSet(weight: weightKg, reps: reps)
    }

    func skipExercise() {
        active?.skipExercise()
    }

    func endEarly() {
        active?.endEarly()
    }

    /// Saves the finished workout (if anything was logged) and plans the next one.
    func finish() {
        guard let finished = active else { return }
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
        replan()
        if let saveProblem { problem = saveProblem }
    }

    private func replan() {
        do {
            let catalog = try Catalog.bundled()
            let history = try store?.load() ?? []
            plan = Engine.generateWorkout(catalog: catalog, gymEquipment: SampleData.gym,
                                          minutes: 45, history: history)
            problem = store == nil ? "Workouts can't be saved on this watch right now." : nil
        } catch {
            plan = nil
            problem = "Your workout history couldn't be read, so today's plan isn't ready."
        }
    }
}
