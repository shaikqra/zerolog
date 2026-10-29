import Foundation

/// Progress numbers worth celebrating. These are the "wins" the design system
/// reserves yellow for, and nothing currently uses it.
///
/// Every value here is computed from sets the user already logged. No AI, no
/// estimates presented as facts.
public enum Strength {

    /// Epley estimated one-rep max: the number lifters actually care about.
    ///
    /// Only meaningful for sets of roughly 1-12 reps. Past that the formula
    /// drifts badly, so it returns nil rather than printing a confident lie --
    /// the same honesty rule the calorie ranges follow.
    public static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= 12 else { return nil }
        if reps == 1 { return round2(weight) }
        return round2(weight * (1 + Double(reps) / 30))
    }

    /// Best estimated 1RM across every logged set of one exercise, in kg.
    public static func bestEstimatedOneRepMaxKg(history: [Session], exerciseId: String) -> Double? {
        var best: Double?
        for session in history {
            for logged in session.exercises where logged.exerciseId == exerciseId {
                for set in logged.sets {
                    if let e1rm = estimatedOneRepMax(weight: set.weightKg, reps: set.reps) {
                        best = max(best ?? 0, e1rm)
                    }
                }
            }
        }
        return best
    }

    /// Total weight moved in a session, in kg. The usual proxy for how hard a
    /// session actually was, and the input a fuelling recommendation needs.
    public static func volumeKg(_ session: Session) -> Double {
        round2(session.exercises.reduce(0.0) { total, logged in
            total + logged.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        })
    }

    /// True when this set beats every previous estimated 1RM for the exercise.
    /// `history` must exclude the set being tested.
    public static func isPersonalBest(history: [Session], exerciseId: String,
                                      weightKg: Double, reps: Int) -> Bool {
        guard let candidate = estimatedOneRepMax(weight: weightKg, reps: reps) else { return false }
        guard let previous = bestEstimatedOneRepMaxKg(history: history, exerciseId: exerciseId) else {
            return false   // first ever set of an exercise is not a "best", it is a baseline
        }
        return candidate > previous
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrEven) / 100
    }
}
