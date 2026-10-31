import XCTest
@testable import ZeroLogCore

/// Fixing a mis-tap. Before this there was no way: confirm the wrong weight and
/// it stayed in the training record forever — and because the engine reads
/// history to pick the next weight, one wrong number kept distorting every
/// future session.
final class HistoryEditTests: XCTestCase {

    private func history() -> [Session] {
        [
            Session(date: "2026-11-09", sessionType: "push", exercises: [
                LoggedExercise(exerciseId: "bench_press", sets: [
                    LoggedSet(weightKg: 60, reps: 10),
                    LoggedSet(weightKg: 60, reps: 9),
                ]),
                LoggedExercise(exerciseId: "overhead_press", sets: [
                    LoggedSet(weightKg: 35, reps: 8),
                ]),
            ]),
            Session(date: "2026-11-11", sessionType: "pull", exercises: [
                LoggedExercise(exerciseId: "barbell_row", sets: [
                    LoggedSet(weightKg: 50, reps: 10),
                ]),
            ]),
        ]
    }

    // MARK: - Editing

    func testEditingChangesOnlyTheTargetedSet() {
        let edited = HistoryEdit.update(history(),
                                        at: SetAddress(session: 0, exercise: 0, set: 1),
                                        weightKg: 62.5, reps: 8)
        XCTAssertEqual(edited[0].exercises[0].sets[1], LoggedSet(weightKg: 62.5, reps: 8))
        XCTAssertEqual(edited[0].exercises[0].sets[0], LoggedSet(weightKg: 60, reps: 10))
        XCTAssertEqual(edited[0].exercises[1], history()[0].exercises[1])
        XCTAssertEqual(edited[1], history()[1])
    }

    /// Rejects rather than clamps. A silently corrected edit is worse than a
    /// refused one: the user believes they fixed it and the engine disagrees.
    func testImpossibleValuesAreRefusedNotClamped() {
        let start = history()
        for (weight, reps) in [(60.0, 0), (60.0, -3), (-10.0, 8),
                               (Double.nan, 8), (Double.infinity, 8)] {
            let result = HistoryEdit.update(start,
                                            at: SetAddress(session: 0, exercise: 0, set: 0),
                                            weightKg: weight, reps: reps)
            XCTAssertEqual(result, start, "\(weight)kg x \(reps) should have been refused")
        }
    }

    /// Zero is legitimate: bodyweight movements log no external load.
    func testZeroWeightIsAllowedBecauseBodyweightMovementsExist() {
        let edited = HistoryEdit.update(history(),
                                        at: SetAddress(session: 0, exercise: 0, set: 0),
                                        weightKg: 0, reps: 12)
        XCTAssertEqual(edited[0].exercises[0].sets[0], LoggedSet(weightKg: 0, reps: 12))
    }

    /// An out-of-range address must never crash. These indices come from a
    /// list that may have been edited a moment earlier.
    func testOutOfRangeAddressesAreIgnoredRatherThanCrashing() {
        let start = history()
        let bad = [SetAddress(session: 9, exercise: 0, set: 0),
                   SetAddress(session: 0, exercise: 9, set: 0),
                   SetAddress(session: 0, exercise: 0, set: 9),
                   SetAddress(session: -1, exercise: 0, set: 0),
                   SetAddress(session: 0, exercise: -1, set: -1)]
        for address in bad {
            XCTAssertEqual(HistoryEdit.update(start, at: address, weightKg: 50, reps: 5), start)
            XCTAssertEqual(HistoryEdit.delete(start, at: address), start)
            XCTAssertNil(HistoryEdit.read(start, at: address))
        }
    }

    // MARK: - Deleting

    func testDeletingOneSetLeavesTheRest() {
        let after = HistoryEdit.delete(history(),
                                       at: SetAddress(session: 0, exercise: 0, set: 0))
        XCTAssertEqual(after[0].exercises[0].sets, [LoggedSet(weightKg: 60, reps: 9)])
        XCTAssertEqual(after[0].exercises.count, 2)
        XCTAssertEqual(after.count, 2)
    }

    /// An exercise with no sets is not harmless: the progression reader would
    /// see "performed, zero reps".
    func testDeletingTheLastSetRemovesTheExercise() {
        let after = HistoryEdit.delete(history(),
                                       at: SetAddress(session: 0, exercise: 1, set: 0))
        XCTAssertEqual(after[0].exercises.count, 1)
        XCTAssertEqual(after[0].exercises.map(\.exerciseId), ["bench_press"])
    }

    /// A session with no exercises still advances the push/pull/legs rotation,
    /// so it must go too.
    func testDeletingTheLastExerciseRemovesTheSession() {
        let after = HistoryEdit.delete(history(),
                                       at: SetAddress(session: 1, exercise: 0, set: 0))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.map(\.date), ["2026-11-09"])
    }

    func testDeletingEverythingLeavesCleanEmptyHistory() {
        var current = history()
        var guard_ = 0
        while !current.isEmpty && guard_ < 50 {
            current = HistoryEdit.delete(current, at: SetAddress(session: 0, exercise: 0, set: 0))
            guard_ += 1
        }
        XCTAssertTrue(current.isEmpty)
        XCTAssertLessThan(guard_, 50, "deletion failed to make progress")
    }

    // MARK: - The reason shown to the user

    func testDeleteIsDescribedIncludingItsSideEffects() {
        let start = history()
        let plain = HistoryEdit.describeDelete(start, at: SetAddress(session: 0, exercise: 0, set: 0),
                                               unit: .kg)
        XCTAssertEqual(plain, "Delete 10 × 60 kg?")

        let lastOfExercise = HistoryEdit.describeDelete(
            start, at: SetAddress(session: 0, exercise: 1, set: 0), unit: .kg)
        XCTAssertTrue(lastOfExercise?.contains("only set of that exercise") ?? false,
                      "got: \(lastOfExercise ?? "nil")")

        let lastOfSession = HistoryEdit.describeDelete(
            start, at: SetAddress(session: 1, exercise: 0, set: 0), unit: .kg)
        XCTAssertTrue(lastOfSession?.contains("whole workout goes too") ?? false,
                      "got: \(lastOfSession ?? "nil")")

        XCTAssertNil(HistoryEdit.describeDelete(start, at: SetAddress(session: 9, exercise: 0, set: 0),
                                                unit: .kg))
    }

    func testDescriptionUsesTheUsersUnit() {
        let text = HistoryEdit.describeDelete(history(),
                                              at: SetAddress(session: 0, exercise: 0, set: 0),
                                              unit: .lb)
        XCTAssertTrue(text?.contains("lb") ?? false, "got: \(text ?? "nil")")
        XCTAssertFalse(text?.contains("60 kg") ?? true)
    }

    // MARK: - Why it matters: the plan follows the correction

    /// The real payoff. A set fat-fingered as 100 kg instead of 10 kg would
    /// otherwise hold the plan at a weight the user cannot lift, forever.
    func testFixingAFatFingeredSetFixesTheNextWorkout() throws {
        let catalog = try Catalog.bundled()
        let gym: Set<String> = ["barbell", "rack", "bench"]
        let wrong = [Session(date: "2026-11-09", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [
                LoggedSet(weightKg: 100, reps: 10),   // meant 10 kg
                LoggedSet(weightKg: 100, reps: 10),
            ])
        ])]

        let badPlan = Engine.generateWorkout(catalog: catalog, gymEquipment: gym, minutes: 45,
                                             history: wrong, sessionType: "push")
        let badBench = try XCTUnwrap(badPlan.exercises.first { $0.exerciseId == "bench_press" })
        XCTAssertGreaterThan(try XCTUnwrap(badBench.weight), 100)

        var fixed = HistoryEdit.update(wrong, at: SetAddress(session: 0, exercise: 0, set: 0),
                                       weightKg: 10, reps: 10)
        fixed = HistoryEdit.update(fixed, at: SetAddress(session: 0, exercise: 0, set: 1),
                                   weightKg: 10, reps: 10)

        let goodPlan = Engine.generateWorkout(catalog: catalog, gymEquipment: gym, minutes: 45,
                                              history: fixed, sessionType: "push")
        let goodBench = try XCTUnwrap(goodPlan.exercises.first { $0.exerciseId == "bench_press" })
        XCTAssertLessThan(try XCTUnwrap(goodBench.weight), 20,
                          "the plan should follow the correction, not the typo")
    }

    // MARK: - Persistence

    func testEditedHistorySurvivesARewrite() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-hist-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)

        try store.replaceAll(history())
        XCTAssertEqual(try store.load(), history())

        let trimmed = HistoryEdit.delete(history(), at: SetAddress(session: 1, exercise: 0, set: 0))
        try store.replaceAll(trimmed)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.count, 1, "the deleted session came back after a reload")
        XCTAssertEqual(reloaded, trimmed)
    }

    func testRewritingEmptyHistoryIsValid() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-hist-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)
        try store.replaceAll([])
        XCTAssertEqual(try store.load(), [])
    }
}
