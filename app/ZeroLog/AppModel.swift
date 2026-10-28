import Foundation
import Observation
import ZeroLogCore

/// What the user told us about their gym.
struct UserSettings: Codable, Equatable {
    var equipment: Set<String>
    var minutes: Int
    var unit: WeightUnit

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

    private let store: HistoryStore?
    private let settingsKey = "settings"

    init() {
        store = try? HistoryStore.standard()
        catalog = try? Catalog.bundled()
        if let data = UserDefaults.standard.data(forKey: settingsKey) {
            settings = try? JSONDecoder().decode(UserSettings.self, from: data)
        }
        refresh()
    }

    func updateSettings(_ new: UserSettings) {
        settings = new
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        refresh()
    }

    func exerciseName(_ id: String) -> String {
        catalog?.exercises.first { $0.id == id }?.name ?? id
    }

    // MARK: Workout in progress

    func start() {
        guard let plan else { return }
        active = ActiveWorkout(plan: plan, date: Today.dateString())
    }

    func confirm(weight: Double, reps: Int) {
        active?.confirmSet(weight: weight, reps: reps)
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
        plan = Engine.generateWorkout(catalog: catalog, gymEquipment: current.equipment,
                                      minutes: current.minutes, history: history, unit: current.unit)
    }
}
