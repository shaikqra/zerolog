import Foundation

/// ZeroLog workout engine. Single source of truth for every number the user sees.
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
        sessionType: String? = nil,
        unit: WeightUnit = .kg,
        bodyweightKg: Double? = nil,
        experience: TrainingExperience = .novice
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
        var plan = chosen.map {
            prescribe($0, history: history, recovery: recovery, unit: unit,
                      bodyweightKg: bodyweightKg, experience: experience)
        }

        // 3. Shrink the workout until it fits the time available.
        fitToTime(&plan, minutes: minutes, skipped: &skipped)

        let minutesEstimate = (Double(estimateSeconds(plan)) / 60).rounded(.toNearestOrEven)
        return Workout(sessionType: type, unit: unit, estimatedMinutes: Int(minutesEstimate),
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

    /// A past set in the user's unit.
    typealias PastSet = (weight: Double, reps: Int)

    /// Past sets in the user's unit, snapped to the nearest weight they can load.
    /// This is what makes switching between kg and lb give sensible plates.
    static func inUnit(_ sets: [LoggedSet], unit: WeightUnit, step: Double) -> [PastSet] {
        sets.map { (weight: roundTo(unit.fromKg($0.weightKg), step: step), reps: $0.reps) }
    }

    static func workingWeight(_ sets: [PastSet]) -> Double {
        sets.map { $0.weight }.max() ?? 0
    }

    static func reps(_ sets: [PastSet], at weight: Double) -> [Int] {
        sets.filter { $0.weight == weight }.map { $0.reps }
    }

    static func prescribe(_ ex: Exercise, history: [Session], recovery: Recovery, unit: WeightUnit,
                          bodyweightKg: Double? = nil,
                          experience: TrainingExperience = .novice) -> PlannedExercise {
        let low = ex.repRange[0], high = ex.repRange[1]
        let inc = ex.increment(in: unit)
        let sets = recovery == .normal ? ex.sets : max(minSets, ex.sets - 1)
        var previous: Double?

        func make(_ weight: Double?, _ target: Int, _ reason: String, change: WeightChange? = nil) -> PlannedExercise {
            PlannedExercise(exerciseId: ex.id, name: ex.name, detectable: ex.detectable,
                            repProfile: ex.repProfile, sets: sets,
                            weight: weight, targetReps: target, reason: reason, increment: inc,
                            previousWeight: previous, change: change, kind: ex.kind, repRange: ex.repRange)
        }

        let past = sessionsWith(history, exerciseId: ex.id).map { inUnit($0, unit: unit, step: inc) }
        guard let last = past.first else {
            // Day one. Suggest a weight when there is a defensible basis for
            // one, because the alternative -- asking the user to guess four or
            // five numbers -- is the worst moment in an app whose promise is
            // that they never type anything.
            if let suggested = StartingWeight.suggest(for: ex, bodyweightKg: bodyweightKg,
                                                      experience: experience, unit: unit) {
                return make(suggested, low, StartingWeight.reason(target: low, unit: unit))
            }
            if ex.isBodyweightLoaded {
                return make(0, low, "Just your bodyweight. Aim for \(low)-\(high) reps.")
            }
            return make(nil, low, "First time: pick a weight you can lift for \(low)-\(high) reps with 2 to spare.")
        }

        let weight = workingWeight(last)
        previous = weight
        let fewest = reps(last, at: weight).min() ?? 0

        if fewest >= high {
            if recovery == .low {
                return make(weight, high,
                            "You earned an increase, but recovery is low today: holding at \(format(weight)) \(unit.rawValue).")
            }
            return make(roundTo(weight + inc, step: inc), low,
                        "You hit \(high) reps on every set last time: +\(format(inc)) \(unit.rawValue).",
                        change: .increased)
        }

        let missedLast = fewest < low
        let missedBefore = past.count > 1
            && workingWeight(past[1]) == weight
            && (reps(past[1], at: weight).min() ?? 0) < low
        if missedLast && missedBefore {
            let lighter = (weight * deloadFactor / inc).rounded(.down) * inc
            return make(roundTo(lighter, step: inc), low,
                        "Missed \(low) reps two sessions running: dropping about 10% to rebuild.",
                        change: .deloaded)
        }

        let target = min(high, fewest + 1)
        return make(weight, target, "Same weight as last time; aim for \(target) reps per set.")
    }

    /// The user's Undo on a "What I changed" card: put one exercise back to last time's weight.
    /// Undoing an increase aims for the top of the rep range again; undoing a deload aims for the bottom.
    public static func undoChange(_ workout: Workout, exerciseId: String) -> Workout {
        guard let index = workout.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else { return workout }
        let item = workout.exercises[index]
        guard let change = item.change, let previous = item.previousWeight else { return workout }
        let target = change == .increased ? item.repRange[1] : item.repRange[0]
        var exercises = workout.exercises
        exercises[index] = PlannedExercise(
            exerciseId: item.exerciseId, name: item.name, detectable: item.detectable,
            repProfile: item.repProfile, sets: item.sets,
            weight: previous, targetReps: target,
            reason: "Kept at \(format(previous)) \(workout.unit.rawValue), as you asked. Aim for \(target) reps.",
            increment: item.increment, previousWeight: previous, change: nil, kind: item.kind, repRange: item.repRange)
        return Workout(sessionType: workout.sessionType, unit: workout.unit, estimatedMinutes: workout.estimatedMinutes,
                       exercises: exercises, skipped: workout.skipped)
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

    /// Trims sets EVENLY, then drops whole exercises from the end.
    ///
    /// The old version walked backwards draining each exercise to the floor
    /// before touching the one before it, so a short legs day came out as full
    /// squats, full hinge, and the last movement gutted to two sets. Spreading
    /// the cut keeps the session balanced: every set removed comes off whichever
    /// exercise currently has the most, preferring later exercises on a tie so
    /// the opening compounds stay intact.
    static func fitToTime(_ plan: inout [PlannedExercise], minutes: Int, skipped: inout [SkippedItem]) {
        let budget = minutes * 60
        while estimateSeconds(plan) > budget {
            // The exercise with the most sets, latest in the plan on a tie.
            var target: Int?
            for index in plan.indices where plan[index].sets > minSets {
                if let current = target, plan[index].sets < plan[current].sets { continue }
                target = index
            }
            guard let index = target else { break }
            plan[index].sets -= 1
        }
        while estimateSeconds(plan) > budget && plan.count > 1 {
            let dropped = plan.removeLast()
            skipped.append(SkippedItem(name: dropped.name, reason: "Dropped to fit your time"))
        }
    }
}
