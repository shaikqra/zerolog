import Foundation

/// How long the user has been training. Decides how hard the first suggestion
/// is, and nothing else.
///
/// Kept deliberately small. The progression rule is DOUBLE PROGRESSION -- reps
/// climb inside the range, then the weight goes up -- and that already
/// self-regulates by experience: a novice earns increases nearly every session,
/// an intermediate stays at a weight for weeks because they stop hitting the
/// top of the range. Adding an experience multiplier on top of a rule that
/// already adapts would be tuning the same thing twice.
///
/// Where experience genuinely matters is the COLD START, where there is no
/// history to progress from.
public enum TrainingExperience: String, Codable, CaseIterable, Sendable {
    /// Under about six months, or never trained with a barbell.
    case novice
    /// Trained before, coming back after a break.
    case returning
    /// Training consistently for a year or more.
    case experienced

    /// Multiplier on the suggested opening weight.
    ///
    /// Returning lifters get LESS than novices relative to their old strength,
    /// because the dangerous case is someone who used to bench 100 kg loading
    /// 100 kg on their first session back. Muscle memory returns faster than
    /// tendon and joint readiness.
    var startMultiplier: Double {
        switch self {
        case .novice: return 1.0
        case .returning: return 1.15
        case .experienced: return 1.4
        }
    }

    public var label: String {
        switch self {
        case .novice: return "New to lifting"
        case .returning: return "Coming back after a break"
        case .experienced: return "Training regularly for a year or more"
        }
    }
}

/// The opening weight for an exercise the user has never logged.
///
/// WHY THIS EXISTS: before it, every exercise on day one said "First time: pick
/// a weight you can lift for 8-12 reps." A first session was four or five
/// guesses, typed in, by someone using an app whose entire promise is that they
/// never type anything. It was the worst moment in the product.
///
/// SAFETY ASYMMETRY, and the reason every ratio is conservative: starting too
/// light costs one easy session. Starting too heavy risks injury on a movement
/// the user may never have performed. So the ratios sit BELOW common novice
/// standards, and the wording always invites the user to change the number.
/// This is a starting point, never a prescription, and never a claim about what
/// anyone should be able to lift.
public enum StartingWeight {

    /// nil when we have no defensible basis -- no bodyweight recorded, or a
    /// movement loaded by the body itself. nil means "ask", which is the
    /// honest fallback rather than a guess dressed up as a suggestion.
    public static func suggest(for exercise: Exercise,
                               bodyweightKg: Double?,
                               experience: TrainingExperience,
                               unit: WeightUnit) -> Double? {
        guard let bodyweightKg, bodyweightKg > 0 else { return nil }
        guard let ratio = exercise.startRatio, ratio > 0 else { return nil }

        let raw = bodyweightKg * ratio * experience.startMultiplier
        let step = exercise.increment(in: unit)
        let inUserUnit = unit.fromKg(raw)

        // Round DOWN to a loadable weight. Rounding up could hand someone a
        // heavier first set than intended, which is the direction that hurts.
        let rounded = (inUserUnit / step).rounded(.down) * step

        // Never suggest less than the empty implement.
        let floor = minimumLoad(for: exercise, unit: unit)
        return max(rounded, floor)
    }

    /// An empty barbell is 20 kg / 45 lb, and suggesting less is nonsense.
    /// Dumbbells and machines can go near zero, so they have no floor.
    static func minimumLoad(for exercise: Exercise, unit: WeightUnit) -> Double {
        guard exercise.equipment.contains("barbell") else { return 0 }
        return unit == .kg ? 20 : 45
    }

    /// The sentence shown with the suggestion. States that it is a starting
    /// point and that changing it is expected -- the product rule is that every
    /// automatic number is shown with its reason.
    public static func reason(target: Int, unit: WeightUnit) -> String {
        "Starting point from your bodyweight. Aim for \(target) reps, and change it if it feels wrong."
    }
}
