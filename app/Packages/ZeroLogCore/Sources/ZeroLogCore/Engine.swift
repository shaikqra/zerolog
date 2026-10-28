import Foundation

/// ZeroLog workout engine: Swift port of core/engine.py.
/// Builds today's workout only from the exercise database, past sessions and fixed rules.
/// Nothing is free-written, and the same inputs always give the same workout.
public enum Engine {
    static let warmUpSeconds = 5 * 60
    static let workSecondsPerSet = 45
    static let restSeconds = ["compound": 150, "isolation": 90]
    static let minSets = 2
    static let deloadFactor = 0.9

    /// Rotate push -> pull -> legs, continuing from the last session.
    public static func nextSessionType(catalog: Catalog, history: [Session]) -> String {
        let order = catalog.sessions["order"] ?? []
        guard let last = history.last?.sessionType, let index = order.firstIndex(of: last) else {
            return order.first ?? ""
        }
        return order[(index + 1) % order.count]
    }

    public static func generateWorkout(
        catalog: Catalog,
        gymEquipment: Set<String>,
        minutes: Int,
        history: [Session],
        recovery: Recovery = .normal,
        sessionType: String? = nil
    ) -> Workout {
        let type = sessionType ?? nextSessionType(catalog: catalog, history: history)

        // 1. Pick one exercise per movement slot, using only this gym's equipment.
        var chosen: [Exercise] = []
        var skipped: [SkippedItem] = []
        for pattern in catalog.sessions[type] ?? [] {
            if let exercise = pickExercise(catalog: catalog, pattern: pattern, gymEquipment: gymEquipment,
                                           history: history, taken: chosen.map(\.id)) {
                chosen.append(exercise)
            } else {
                skipped.append(SkippedItem(name: pattern, reason: "No equipment for this movement at this gym"))
            }
        }

        // 2. Decide weight, reps and sets for each one from past sessions.
        var plan = chosen.map { prescribe($0, history: history, recovery: recovery) }

        // 3. Shrink the workout until it fits the time available.
        fitToTime(&plan, minutes: minutes, skipped: &skipped)

        let minutesEstimate = (Double(estimateSeconds(plan)) / 60).rounded(.toNearestOrEven)
        return Workout(sessionType: type, estimatedMinutes: Int(minutesEstimate),
                       exercises: plan, skipped: skipped)
    }

    static func pickExercise(catalog: Catalog, pattern: String, gymEquipment: Set<String>,
                             history: [Session], taken: [String]) -> Exercise? {
        let candidates = catalog.exercises.filter {
            $0.pattern == pattern && !taken.contains($0.id) && Set($0.equipment).isSubset(of: gymEquipment)
        }
        guard let first = candidates.first else { return nil }
        // Prefer the exercise the user did most recently for this movement, so progression continues.
        for session in history.reversed() {
            for logged in session.exercises {
                if let match = candidates.first(where: { $0.id == logged.exerciseId }) {
                    return match
                }
            }
        }
        return first
    }

    /// Past sets for one exercise, most recent session first.
    static func sessionsWith(_ history: [Session], exerciseId: String) -> [[LoggedSet]] {
        var found: [[LoggedSet]] = []
        for session in history.reversed() {
            for logged in session.exercises where logged.exerciseId == exerciseId && !logged.sets.isEmpty {
                found.append(logged.sets)
            }
        }
        return found
    }

    static func workingWeight(_ sets: [LoggedSet]) -> Double {
        sets.map(\.weightKg).max() ?? 0
    }

    static func reps(_ sets: [LoggedSet], at weight: Double) -> [Int] {
        sets.filter { $0.weightKg == weight }.map(\.reps)
    }

    static func prescribe(_ ex: Exercise, history: [Session], recovery: Recovery) -> PlannedExercise {
        let low = ex.repRange[0], high = ex.repRange[1]
        let inc = ex.incrementKg
        let sets = recovery == .normal ? ex.sets : max(minSets, ex.sets - 1)

        func make(_ weight: Double?, _ target: Int, _ reason: String) -> PlannedExercise {
            PlannedExercise(exerciseId: ex.id, name: ex.name, detectable: ex.detectable, sets: sets,
                            weightKg: weight, targetReps: target, reason: reason, kind: ex.kind)
        }

        let past = sessionsWith(history, exerciseId: ex.id)
        guard let last = past.first else {
            return make(nil, low, "First time: pick a weight you can lift for \(low)-\(high) reps with 2 to spare.")
        }

        let weight = workingWeight(last)
        let fewest = reps(last, at: weight).min() ?? 0

        if fewest >= high {
            if recovery == .low {
                return make(weight, high,
                            "You earned an increase, but recovery is low today: holding at \(format(weight)) kg.")
            }
            return make(roundTo(weight + inc, step: inc), low,
                        "You hit \(high) reps on every set last time: +\(format(inc)) kg.")
        }

        let missedLast = fewest < low
        let missedBefore = past.count > 1
            && workingWeight(past[1]) == weight
            && (reps(past[1], at: weight).min() ?? 0) < low
        if missedLast && missedBefore {
            let lighter = (weight * deloadFactor / inc).rounded(.down) * inc
            return make(roundTo(lighter, step: inc), low,
                        "Missed \(low) reps two sessions running: dropping about 10% to rebuild.")
        }

        let target = min(high, fewest + 1)
        return make(weight, target, "Same weight as last time; aim for \(target) reps per set.")
    }

    static func roundTo(_ weight: Double, step: Double) -> Double {
        let stepped = (weight / step).rounded(.toNearestOrEven) * step
        return (stepped * 100).rounded(.toNearestOrEven) / 100
    }

    /// 60.0 -> "60", 62.5 -> "62.5" (matches Python's {:g}).
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    static func estimateSeconds(_ plan: [PlannedExercise]) -> Int {
        plan.reduce(warmUpSeconds) { total, item in
            total + item.sets * (workSecondsPerSet + (restSeconds[item.kind] ?? 0))
        }
    }

    /// First trim sets (last exercise first, down to 2), then drop exercises from the end.
    static func fitToTime(_ plan: inout [PlannedExercise], minutes: Int, skipped: inout [SkippedItem]) {
        let budget = minutes * 60
        for index in plan.indices.reversed() {
            while estimateSeconds(plan) > budget && plan[index].sets > minSets {
                plan[index].sets -= 1
            }
        }
        while estimateSeconds(plan) > budget && plan.count > 1 {
            let dropped = plan.removeLast()
            skipped.append(SkippedItem(name: dropped.name, reason: "Dropped to fit your time"))
        }
    }
}
