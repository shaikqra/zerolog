import XCTest
@testable import ZeroLogCore

/// Undo of a confirmed set, including one the watch logged by itself.
///
/// The awkward case is undoing the LAST set of an exercise, because confirming
/// it also moved the position to the next exercise. Undo has to put both back,
/// which is why the position is recorded before it changes rather than inferred
/// afterwards.
final class UndoSetTests: XCTestCase {

    private func planned(_ id: String, name: String, sets: Int) -> PlannedExercise {
        PlannedExercise(exerciseId: id, name: name, detectable: true, repProfile: nil,
                        sets: sets, weight: 60, targetReps: 8, reason: "test",
                        increment: 2.5, previousWeight: nil, change: nil,
                        kind: "compound", repRange: [5, 8])
    }

    private func workout(sets: Int = 3) -> ActiveWorkout {
        let plan = Workout(sessionType: "legs", unit: .kg, estimatedMinutes: 45,
                           exercises: [planned("back_squat", name: "Back squat", sets: sets),
                                       planned("romanian_deadlift", name: "RDL", sets: sets)],
                           skipped: [])
        return ActiveWorkout(plan: plan, date: "2026-10-30")
    }

    func testNothingToUndoOnAFreshWorkout() {
        var w = workout()
        XCTAssertFalse(w.canUndo)
        XCTAssertFalse(w.undoLastSet())
        XCTAssertEqual(w.totalSetsLogged, 0)
    }

    func testUndoingAMidExerciseSetStepsTheSetNumberBack() {
        var w = workout()
        w.confirmSet(weight: 60, reps: 8)
        XCTAssertEqual(w.setNumber, 2)
        XCTAssertEqual(w.totalSetsLogged, 1)

        XCTAssertTrue(w.undoLastSet())
        XCTAssertEqual(w.setNumber, 1, "the set number must go back")
        XCTAssertEqual(w.totalSetsLogged, 0, "the set must be gone")
        XCTAssertEqual(w.current?.exerciseId, "back_squat")
    }

    /// The case that breaks naive implementations: undoing across an exercise
    /// boundary must come back to the exercise you were on.
    ///
    /// Advancing is now an explicit step, so this crosses the boundary via
    /// nextExercise() rather than as a side effect of the last set.
    func testUndoingAcrossAnExerciseBoundaryComesBack() {
        var w = workout(sets: 2)
        w.confirmSet(weight: 60, reps: 8)
        w.confirmSet(weight: 60, reps: 8)
        XCTAssertTrue(w.nextExercise())
        XCTAssertEqual(w.current?.exerciseId, "romanian_deadlift", "should have advanced")
        XCTAssertEqual(w.setNumber, 1)

        XCTAssertTrue(w.undoLastSet())
        XCTAssertEqual(w.current?.exerciseId, "back_squat", "undo must come back to the squat")
        XCTAssertEqual(w.setNumber, 2, "and to the set that was undone")
        XCTAssertEqual(w.totalSetsLogged, 1, "exactly one set removed, not two")
    }

    /// Moving to the next exercise must not become an undoable "action" that
    /// eats a set. Undo means one thing: take back the last SET.
    func testMovingOnThenUndoingRemovesExactlyOneSet() {
        var w = workout(sets: 2)
        w.confirmSet(weight: 60, reps: 8)
        w.confirmSet(weight: 60, reps: 8)
        XCTAssertEqual(w.totalSetsLogged, 2)
        XCTAssertTrue(w.nextExercise())
        XCTAssertTrue(w.undoLastSet())
        XCTAssertEqual(w.totalSetsLogged, 1,
                       "one undo, one set -- moving on must not consume an undo")
    }

    /// Undoing the only set of an exercise must not leave an empty exercise
    /// behind in the saved history.
    func testUndoingTheOnlySetRemovesTheExerciseEntirely() {
        var w = workout()
        w.confirmSet(weight: 60, reps: 8)
        XCTAssertEqual(w.session.exercises.count, 1)

        XCTAssertTrue(w.undoLastSet())
        XCTAssertTrue(w.session.exercises.isEmpty,
                      "an exercise with no sets should not reach history")
    }

    func testUndoThenLogAgainRecordsTheCorrectedNumber() {
        var w = workout()
        w.confirmSet(weight: 60, reps: 12)      // what the watch guessed
        w.undoLastSet()
        w.confirmSet(weight: 60, reps: 8)       // what actually happened

        XCTAssertEqual(w.totalSetsLogged, 1)
        XCTAssertEqual(w.session.exercises.first?.sets.first?.reps, 8)
    }

    func testUndoWalksBackSetByySetAndThenStops() {
        var w = workout(sets: 3)
        w.confirmSet(weight: 60, reps: 8)
        w.confirmSet(weight: 60, reps: 8)
        w.confirmSet(weight: 60, reps: 8)
        // Stays put now: finishing the planned sets no longer moves you on by
        // itself, so an extra set is always possible.
        XCTAssertEqual(w.current?.exerciseId, "back_squat")
        XCTAssertTrue(w.hasFinishedPlannedSets)

        XCTAssertTrue(w.undoLastSet())
        XCTAssertTrue(w.undoLastSet())
        XCTAssertTrue(w.undoLastSet())
        XCTAssertFalse(w.undoLastSet(), "nothing left to undo")
        XCTAssertFalse(w.canUndo)
        XCTAssertEqual(w.totalSetsLogged, 0)
        XCTAssertEqual(w.setNumber, 1)
        XCTAssertEqual(w.current?.exerciseId, "back_squat")
    }

    /// A rejected set (zero reps) must not leave an undo frame behind, or undo
    /// would silently remove a real set instead.
    func testARejectedSetLeavesNothingToUndo() {
        var w = workout()
        XCTAssertFalse(w.confirmSet(weight: 60, reps: 0))
        XCTAssertFalse(w.canUndo, "a set that was never recorded cannot be undone")
    }
}
