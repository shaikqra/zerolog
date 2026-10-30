import Foundation

/// What to do about a set the watch spotted.
///
/// Separated from the UI so the rules are testable on Linux, and separated from
/// `SetDetector` because "can we count this?" and "should we log it without
/// asking?" are different questions. The detector answers the first honestly;
/// this decides whether that answer is good enough to act on alone.
public enum AutoLogDecision: Equatable, Sendable {
    /// Good enough to record with no interaction. `note` is shown afterwards
    /// with an Undo, never as a silent change.
    case logSilently(reps: Int, weight: Double, note: String)
    /// Show the number and take one tap. Still beats typing.
    case askToConfirm(reps: Int, weight: Double, note: String)
    /// Do not act. `reason` is for diagnostics; the user keeps the normal card
    /// and is not interrupted by a guess.
    case ignore(reason: String)
}

public enum AutoLog {

    /// Decides what a detected set earns.
    ///
    /// The order of these checks is the product. Each `ignore` is a case where
    /// logging anything would be worse than logging nothing, because a wrong
    /// number in your history is harder to notice -- and harder to trust again --
    /// than a missing one.
    public static func decide(detected: DetectedSet,
                              exercise: PlannedExercise?,
                              suggestedWeight: Double?,
                              unit: WeightUnit) -> AutoLogDecision {

        guard let exercise else {
            return .ignore(reason: "No exercise in progress")
        }

        // Some movements keep the wrist still -- a leg press or a hanging knee
        // raise. The catalogue says so; believe it rather than the signal.
        guard exercise.detectable else {
            return .ignore(reason: "\(exercise.name) can't be counted from your wrist")
        }

        // The detector must have been calibrated for THIS exercise. If the
        // profile does not match, the count came from the wrong settings and the
        // confidence attached to it means nothing. This is the guard against the
        // failure mode where both estimators agree on a wrong number.
        guard detected.repProfile == exercise.repProfile else {
            return .ignore(reason: "Counted with the wrong settings for \(exercise.name)")
        }

        guard detected.reps > 0 else {
            return .ignore(reason: "No reps counted")
        }

        // Without history there is no weight to attach, and the app must never
        // invent one. Ask once; after that the engine knows.
        guard let weight = suggestedWeight else {
            return .askToConfirm(reps: detected.reps, weight: 0,
                                 note: "Looked like \(detected.reps) reps. Set your weight to log it.")
        }

        switch detected.confidence {
        case .high:
            return .logSilently(reps: detected.reps, weight: weight,
                                note: "\(detected.reps) reps at \(format(weight, unit)). Counted from your wrist.")
        case .medium:
            return .askToConfirm(reps: detected.reps, weight: weight,
                                 note: "Looked like \(detected.reps) reps. Tap to confirm.")
        case .low:
            // Deliberately silent. Interrupting with a number we do not trust
            // trains the user to stop believing the ones we do.
            return .ignore(reason: "Not sure enough to suggest a number")
        }
    }

    static func format(_ weight: Double, _ unit: WeightUnit) -> String {
        let rounded = (weight * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(text) \(unit.rawValue)"
    }
}
