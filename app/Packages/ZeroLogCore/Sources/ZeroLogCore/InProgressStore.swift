import Foundation

/// Keeps the workout in progress on disk, so losing the app does not lose the
/// session.
///
/// This exists because watchOS terminates apps routinely: low memory, a long
/// rest between sets, the user switching to Music. `ActiveWorkout` lived only in
/// memory, so a termination forty minutes into a session silently discarded
/// every set logged. In a gym that is the worst possible failure -- the work is
/// already done and cannot be redone.
///
/// Written after every set rather than at the end, so a crash costs one set at
/// most. The file is small (a plan plus the sets so far), so the write cost is
/// irrelevant next to what it protects.
public struct InProgressStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// in-progress.json in the app's Application Support folder.
    public static func standard() throws -> InProgressStore {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return InProgressStore(fileURL: folder.appendingPathComponent("in-progress.json"))
    }

    public func save(_ workout: ActiveWorkout) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(workout).write(to: fileURL, options: .atomic)
    }

    /// Returns the saved workout only if it is worth resuming.
    ///
    /// `today` is passed in rather than read from the clock so the rule is
    /// testable. A workout from a previous day is NOT resumed: picking up
    /// Tuesday's leg day on Thursday would log sets against the wrong date and
    /// poison the progression history. It is deleted instead.
    ///
    /// A finished workout is also not resumed -- it either saved to history
    /// already or was abandoned, and in both cases there is nothing to continue.
    public func resumable(today: String) throws -> ActiveWorkout? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let saved: ActiveWorkout
        do {
            saved = try JSONDecoder().decode(ActiveWorkout.self, from: Data(contentsOf: fileURL))
        } catch {
            // A damaged file must not block the app forever. Drop it and start clean.
            clear()
            return nil
        }
        guard saved.date == today, !saved.isFinished, saved.totalSetsLogged > 0 else {
            clear()
            return nil
        }
        return saved
    }

    /// Called once the workout is saved to history, or abandoned.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
