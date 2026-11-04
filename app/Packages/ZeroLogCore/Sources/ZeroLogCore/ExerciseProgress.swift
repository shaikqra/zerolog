import Foundation

/// One session's worth of a single exercise, for showing progress over time.
public struct ExerciseProgressPoint: Equatable, Sendable {
    public let date: String
    /// Heaviest weight worked that session, in the user's unit.
    ///
    /// The same definition the planner uses, so the progress screen can never
    /// disagree with the weight the app then suggests. Two different ideas of
    /// "your working weight" would make one of the screens a liar.
    public let workingWeight: Double
    /// Most reps achieved at that weight.
    public let bestReps: Int
    public let sets: Int
    /// Weight times reps across every set, in the user's unit.
    public let volume: Double
    /// True when no earlier session reached this weight.
    public let isRecord: Bool

    public init(date: String, workingWeight: Double, bestReps: Int,
                sets: Int, volume: Double, isRecord: Bool) {
        self.date = date
        self.workingWeight = workingWeight
        self.bestReps = bestReps
        self.sets = sets
        self.volume = volume
        self.isRecord = isRecord
    }
}

/// The history of one movement, oldest first.
public struct ExerciseProgress: Equatable, Sendable {
    public let exerciseId: String
    public let name: String
    public let unit: WeightUnit
    public let points: [ExerciseProgressPoint]

    public init(exerciseId: String, name: String, unit: WeightUnit,
                points: [ExerciseProgressPoint]) {
        self.exerciseId = exerciseId
        self.name = name
        self.unit = unit
        self.points = points
    }

    public var heaviest: Double { points.map(\.workingWeight).max() ?? 0 }
    public var latest: ExerciseProgressPoint? { points.last }

    /// Change from the first session to the latest, in the user's unit.
    ///
    /// nil until there are at least TWO sessions. A single data point is not a
    /// trend, and showing "+0" or a flat line on day one implies a lack of
    /// progress that has not had a chance to happen yet -- the same rule the
    /// week summary follows.
    public var changeSinceStart: Double? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.workingWeight - first.workingWeight
    }

    /// Enough history to say anything honest about a direction.
    public var hasTrend: Bool { points.count >= 2 }
}

extension Engine {
    /// Every session containing one exercise, with its dates, oldest first.
    ///
    /// Deliberately separate from `sessionsWith`, which drops dates because the
    /// planner only cares about the most recent sets. Progress is the one place
    /// that needs the timeline.
    public static func progress(for exerciseId: String,
                                name: String,
                                history: [Session],
                                unit: WeightUnit,
                                step: Double) -> ExerciseProgress {
        var points: [ExerciseProgressPoint] = []
        var heaviestSoFar = 0.0

        // history is oldest-first, which is the order a timeline wants.
        for session in history {
            for logged in session.exercises
            where logged.exerciseId == exerciseId && !logged.sets.isEmpty {
                let sets = inUnit(logged.sets, unit: unit, step: step)
                let working = workingWeight(sets)
                let bestReps = reps(sets, at: working).max() ?? 0
                let volume = sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                // Strictly greater: repeating your best is not a new record,
                // and calling it one would cheapen the real thing.
                let isRecord = working > heaviestSoFar
                if isRecord { heaviestSoFar = working }
                points.append(ExerciseProgressPoint(date: session.date,
                                                    workingWeight: working,
                                                    bestReps: bestReps,
                                                    sets: sets.count,
                                                    volume: volume,
                                                    isRecord: isRecord))
            }
        }
        return ExerciseProgress(exerciseId: exerciseId, name: name,
                                unit: unit, points: points)
    }

    /// Every exercise the user has actually logged, most recently trained
    /// first, so the progress list is theirs rather than the catalog's.
    public static func trainedExercises(history: [Session],
                                        catalog: Catalog) -> [Exercise] {
        var seen: [String] = []
        for session in history.reversed() {
            for logged in session.exercises where !logged.sets.isEmpty {
                if !seen.contains(logged.exerciseId) { seen.append(logged.exerciseId) }
            }
        }
        return seen.compactMap { catalog.exercise(id: $0) }
    }
}
