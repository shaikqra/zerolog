import XCTest
@testable import ZeroLogCore

/// Covers two bugs found by reviewing the code rather than by a crash: a
/// workout lost when the app is killed, and a session trimmed unfairly.
final class ResilienceTests: XCTestCase {

    private func planned(_ id: String, sets: Int = 3) -> PlannedExercise {
        PlannedExercise(exerciseId: id, name: id, detectable: true, repProfile: nil,
                        sets: sets, weight: 60, targetReps: 8, reason: "test",
                        increment: 2.5, previousWeight: nil, change: nil,
                        kind: "compound", repRange: [5, 8])
    }

    private func workout(_ ids: [String], sets: Int = 3, date: String = "2026-10-30") -> ActiveWorkout {
        let plan = Workout(sessionType: "legs", unit: .kg, estimatedMinutes: 45,
                           exercises: ids.map { planned($0, sets: sets) }, skipped: [])
        return ActiveWorkout(plan: plan, date: date)
    }

    private func tempStore() -> InProgressStore {
        InProgressStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-progress-\(UUID().uuidString).json"))
    }

    // MARK: - Losing the app must not lose the workout

    /// The failure this prevents: watchOS kills the app forty minutes into a
    /// session and every logged set vanishes. The work is already done and
    /// cannot be redone.
    func testAnInterruptedWorkoutIsResumedWithItsSets() throws {
        let store = tempStore()
        var live = workout(["back_squat", "romanian_deadlift"])
        live.confirmSet(weight: 100, reps: 5)
        live.confirmSet(weight: 100, reps: 5)
        try store.save(live)

        let resumed = try store.resumable(today: "2026-10-30")
        XCTAssertNotNil(resumed)
        XCTAssertEqual(resumed?.totalSetsLogged, 2, "both sets must come back")
        XCTAssertEqual(resumed?.setNumber, 3, "and the position within the exercise")
        XCTAssertEqual(resumed?.current?.exerciseId, "back_squat")
        XCTAssertEqual(resumed?.session.exercises.first?.sets.map(\.reps), [5, 5])
    }

    func testNothingSavedMeansNothingToResume() throws {
        XCTAssertNil(try tempStore().resumable(today: "2026-10-30"))
    }

    /// Resuming Tuesday's leg day on Thursday would log sets against the wrong
    /// date and poison the progression history, which is worse than losing them.
    func testAWorkoutFromAnotherDayIsDiscardedNotResumed() throws {
        let store = tempStore()
        var old = workout(["back_squat"], date: "2026-10-27")
        old.confirmSet(weight: 100, reps: 5)
        try store.save(old)

        XCTAssertNil(try store.resumable(today: "2026-10-30"))
        XCTAssertNil(try store.resumable(today: "2026-10-30"),
                     "and the stale file should have been cleared")
    }

    /// An empty workout is not worth offering to resume.
    func testAWorkoutWithNoSetsIsNotResumed() throws {
        let store = tempStore()
        try store.save(workout(["back_squat"]))
        XCTAssertNil(try store.resumable(today: "2026-10-30"))
    }

    func testAFinishedWorkoutIsNotResumed() throws {
        let store = tempStore()
        var done = workout(["back_squat"])
        done.confirmSet(weight: 100, reps: 5)
        done.endEarly()
        try store.save(done)
        XCTAssertNil(try store.resumable(today: "2026-10-30"))
    }

    /// A damaged file must not wedge the app on every launch.
    func testADamagedFileIsDiscardedRatherThanThrowing() throws {
        let store = tempStore()
        try Data("this is not json".utf8).write(to: store.fileURL)
        XCTAssertNil(try store.resumable(today: "2026-10-30"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path),
                       "the unreadable file should have been removed")
    }

    func testClearRemovesTheResumeFile() throws {
        let store = tempStore()
        var live = workout(["back_squat"])
        live.confirmSet(weight: 100, reps: 5)
        try store.save(live)
        store.clear()
        XCTAssertNil(try store.resumable(today: "2026-10-30"))
    }

    /// Undo has to survive a resume too, or the user cannot take back the set
    /// the watch logged just before the app died.
    func testUndoStillWorksAfterResuming() throws {
        let store = tempStore()
        var live = workout(["back_squat"])
        live.confirmSet(weight: 100, reps: 5)
        live.confirmSet(weight: 100, reps: 5)
        try store.save(live)

        guard var resumed = try store.resumable(today: "2026-10-30") else {
            return XCTFail("expected a resumable workout")
        }
        XCTAssertTrue(resumed.canUndo, "the undo stack must survive encoding")
        XCTAssertTrue(resumed.undoLastSet())
        XCTAssertEqual(resumed.totalSetsLogged, 1)
        XCTAssertEqual(resumed.setNumber, 2)
    }

    // MARK: - Time trimming must be even

    /// The old behaviour drained the last exercise to the floor before touching
    /// any earlier one, so a short legs day came out as full squats, full hinge,
    /// and the last movement gutted.
    func testTrimmingForTimeSpreadsTheCutEvenly() throws {
        let catalog = try Catalog.bundled()
        for minutes in [20, 30, 45] {
            let settings = UserSettings(equipment: ["barbell", "rack", "dumbbells", "bench",
                                                    "cable", "lat_pulldown", "pull_up_bar"],
                                        minutes: minutes, unit: .kg)
            for type in ["push", "pull", "legs"] {
                let plan = Engine.generateWorkout(catalog: catalog,
                                                  gymEquipment: settings.equipment,
                                                  minutes: minutes, history: [],
                                                  sessionType: type)
                let counts = plan.exercises.map(\.sets)
                guard let low = counts.min(), let high = counts.max() else { continue }
                XCTAssertLessThanOrEqual(high - low, 1,
                    "\(type) at \(minutes) min came out as \(counts); the cut should be spread, "
                    + "not taken entirely out of the last exercises")
            }
        }
    }

    /// Trimming must still respect the time budget it was given.
    func testTrimmedWorkoutsStillFitTheTime() throws {
        let catalog = try Catalog.bundled()
        for minutes in [20, 30, 45, 60] {
            let plan = Engine.generateWorkout(
                catalog: catalog,
                gymEquipment: ["barbell", "rack", "dumbbells", "bench", "cable",
                               "lat_pulldown", "pull_up_bar", "leg_press"],
                minutes: minutes, history: [], sessionType: "legs")
            XCTAssertLessThanOrEqual(plan.estimatedMinutes, minutes,
                                     "legs at \(minutes) min estimated \(plan.estimatedMinutes)")
        }
    }

    /// No exercise may be trimmed below the floor while another still has spare
    /// sets to give.
    func testNoExerciseIsCutBelowTheFloorUnnecessarily() throws {
        let catalog = try Catalog.bundled()
        let plan = Engine.generateWorkout(
            catalog: catalog,
            gymEquipment: ["barbell", "rack", "dumbbells", "bench", "cable",
                           "lat_pulldown", "pull_up_bar"],
            minutes: 25, history: [], sessionType: "legs")
        for exercise in plan.exercises {
            XCTAssertGreaterThanOrEqual(exercise.sets, Engine.minSets,
                                        "\(exercise.name) fell below the minimum set count")
        }
    }
}
