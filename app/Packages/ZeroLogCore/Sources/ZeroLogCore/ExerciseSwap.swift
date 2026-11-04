import Foundation

/// Swapping one exercise for another mid-workout.
///
/// The case this exists for is ordinary and constant: the rack is taken, the
/// cable machine has a queue, your shoulder does not like that movement today.
/// Before this, the only option was skipping the exercise entirely, which lost
/// the training AND told the engine you had skipped rather than substituted.
public enum ExerciseSwap {

    /// Movements that train the same thing, with equipment you actually have.
    ///
    /// Matching is on `pattern` (horizontal_push, hinge, squat...) because that
    /// is what makes a substitute legitimate: a horizontal push replaces a
    /// horizontal push. Matching on muscle names or by name similarity would
    /// happily offer a lateral raise for a bench press.
    ///
    /// - Parameter excluding: exercises already in today's workout. Offering
    ///   something the lifter is about to do anyway would quietly halve the
    ///   session's coverage while looking like a helpful suggestion.
    public static func alternatives(to exerciseId: String,
                                    catalog: Catalog,
                                    equipment: Set<String>,
                                    excluding: Set<String> = []) -> [Exercise] {
        guard let current = catalog.exercise(id: exerciseId) else { return [] }
        let skip = excluding.union([exerciseId])

        return catalog.exercises
            .filter { $0.pattern == current.pattern }
            .filter { !skip.contains($0.id) }
            .filter { Set($0.equipment).isSubset(of: equipment) }
            // Same kind first: swapping a compound for an isolation changes what
            // the session is for, so it is offered but never offered first.
            .sorted { a, b in
                let aSame = a.kind == current.kind, bSame = b.kind == current.kind
                if aSame != bSame { return aSame }
                return a.name < b.name
            }
    }

    /// Builds the replacement's plan from ITS OWN history.
    ///
    /// The weight must never carry across. Benching 80 kg does not mean you
    /// dumbbell press 80 kg, and inheriting the number would put a dangerous
    /// suggestion in front of someone mid-session. Routing through
    /// `Engine.prescribe` means the substitute gets the same progression,
    /// first-time handling and bodyweight-based opening weight as any other
    /// exercise -- including "first time: pick a weight" when it has no history.
    public static func plan(_ replacement: Exercise,
                            history: [Session],
                            unit: WeightUnit,
                            recovery: Recovery = .normal,
                            bodyweightKg: Double? = nil,
                            experience: TrainingExperience = .novice) -> PlannedExercise {
        Engine.prescribe(replacement, history: history, recovery: recovery, unit: unit,
                         bodyweightKg: bodyweightKg, experience: experience)
    }
}


