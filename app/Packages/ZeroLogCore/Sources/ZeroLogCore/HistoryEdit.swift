import Foundation

/// Points at one logged set. Positional rather than keyed by date, because two
/// sessions can share a date and two entries can share an exercise id; an
/// address that can be ambiguous will eventually edit the wrong set.
public struct SetAddress: Equatable, Sendable {
    public let session: Int
    public let exercise: Int
    public let set: Int

    public init(session: Int, exercise: Int, set: Int) {
        self.session = session
        self.exercise = exercise
        self.set = set
    }
}

/// Correcting history after the fact.
///
/// WHY THIS EXISTS: there was no way to fix a mis-tap. Confirm the wrong weight
/// and it was in your training record permanently — and because the engine
/// reads history to decide your next weight, ONE WRONG NUMBER KEEPS AFFECTING
/// EVERY FUTURE SESSION. A set logged at 100 kg instead of 10 kg would hold the
/// plan at a weight the user cannot lift, and the only escape was never doing
/// that exercise again. Undo covers the last set only, and only before saving.
///
/// Every function here is pure: history in, history out. The caller persists.
/// That keeps the rules testable on Linux and means a rejected edit cannot
/// half-apply to the file on disk.
public enum HistoryEdit {

    /// Rejects rather than clamps, and returns the input unchanged on anything
    /// out of range. A silently corrected edit is worse than a refused one:
    /// the user believes they fixed the number and the engine disagrees.
    public static func update(_ history: [Session], at address: SetAddress,
                              weightKg: Double, reps: Int) -> [Session] {
        guard reps > 0, weightKg >= 0, weightKg.isFinite else { return history }
        guard var set = read(history, at: address) else { return history }
        var updated = history
        set.weightKg = weightKg
        set.reps = reps
        updated[address.session].exercises[address.exercise].sets[address.set] = set
        return updated
    }

    /// Deleting the last set of an exercise removes the exercise, and the last
    /// exercise of a session removes the session.
    ///
    /// Empty shells are not harmless: an exercise with no sets makes the
    /// progression reader see "performed, zero reps", and a session with no
    /// exercises still advances the push/pull/legs rotation. A deleted set must
    /// leave history looking as though it never happened.
    public static func delete(_ history: [Session], at address: SetAddress) -> [Session] {
        guard read(history, at: address) != nil else { return history }
        var updated = history
        updated[address.session].exercises[address.exercise].sets.remove(at: address.set)
        if updated[address.session].exercises[address.exercise].sets.isEmpty {
            updated[address.session].exercises.remove(at: address.exercise)
        }
        if updated[address.session].exercises.isEmpty {
            updated.remove(at: address.session)
        }
        return updated
    }

    /// Bounds-checked read. Every mutation goes through this, so an invalid
    /// address can never index out of range and crash.
    public static func read(_ history: [Session], at address: SetAddress) -> LoggedSet? {
        guard history.indices.contains(address.session) else { return nil }
        let session = history[address.session]
        guard session.exercises.indices.contains(address.exercise) else { return nil }
        let exercise = session.exercises[address.exercise]
        guard exercise.sets.indices.contains(address.set) else { return nil }
        return exercise.sets[address.set]
    }

    /// Plain-language description of what an edit will change, for a
    /// confirmation. Editing history silently would break the product rule that
    /// every change is shown with its reason — and this change is the user's
    /// own, which makes showing it more important, not less.
    public static func describeDelete(_ history: [Session], at address: SetAddress,
                                      unit: WeightUnit) -> String? {
        guard let set = read(history, at: address) else { return nil }
        let weight = unit.fromKg(set.weightKg).formatted()
        let isLastOfExercise = history[address.session]
            .exercises[address.exercise].sets.count == 1
        let isLastOfSession = isLastOfExercise
            && history[address.session].exercises.count == 1

        let base = "Delete \(set.reps) × \(weight) \(unit.rawValue)?"
        if isLastOfSession { return base + " This was the only set, so the whole workout goes too." }
        if isLastOfExercise { return base + " It was the only set of that exercise." }
        return base
    }
}

extension HistoryStore {
    /// Writes an edited history back in full.
    ///
    /// `append` cannot express a correction, and rewriting the file is the only
    /// honest way to remove something from it.
    public func replaceAll(_ history: [Session]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
