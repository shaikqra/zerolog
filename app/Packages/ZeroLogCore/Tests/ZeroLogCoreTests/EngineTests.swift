import XCTest
@testable import ZeroLogCore

/// Same rules as core/test_engine.py. If a rule changes, change it in both places.
final class EngineTests: XCTestCase {
    private var catalog: Catalog!
    private let fullGym: Set<String> = ["barbell", "bench", "rack", "dumbbells", "cable", "lat_pulldown", "leg_press"]
    private let dumbbellsOnly: Set<String> = ["dumbbells", "bench"]

    override func setUpWithError() throws {
        catalog = try Catalog.bundled()
    }

    private func session(_ date: String, _ type: String, _ id: String, _ weight: Double, _ reps: [Int]) -> Session {
        Session(date: date, sessionType: type, exercises: [
            LoggedExercise(exerciseId: id, sets: reps.map { LoggedSet(weightKg: weight, reps: $0) }),
        ])
    }

    private func workout(minutes: Int = 60, history: [Session] = [], recovery: Recovery = .normal,
                         type: String? = "push", gym: Set<String>? = nil, unit: WeightUnit = .kg) -> Workout {
        Engine.generateWorkout(catalog: catalog, gymEquipment: gym ?? fullGym, minutes: minutes,
                               history: history, recovery: recovery, sessionType: type, unit: unit)
    }

    private func find(_ workout: Workout, _ id: String) throws -> PlannedExercise {
        try XCTUnwrap(workout.exercises.first { $0.exerciseId == id })
    }

    // MARK: Database

    func testDatabaseLoads() {
        XCTAssertEqual(catalog.exercises.count, 19)
        XCTAssertEqual(catalog.sessions["order"], ["push", "pull", "legs"])
    }

    func testEveryExerciseUsesKnownEquipment() {
        let known = Set(catalog.equipmentTypes.map(\.id))
        XCTAssertTrue(known.contains("lat_pulldown"))  // ids keep their underscores
        for exercise in catalog.exercises {
            XCTAssertTrue(Set(exercise.equipment).isSubset(of: known), exercise.id)
        }
    }

    func testEveryExerciseHasThreeOrFourFormCues() {
        for exercise in catalog.exercises {
            XCTAssertTrue((3...4).contains(exercise.cues.count), exercise.id)
            XCTAssertFalse(exercise.cues.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, exercise.id)
        }
    }

    // MARK: Selection

    func testOnlyUsesEquipmentTheGymHas() {
        let equipmentById = Dictionary(uniqueKeysWithValues: catalog.exercises.map { ($0.id, Set($0.equipment)) })
        for type in ["push", "pull", "legs"] {
            for item in workout(minutes: 90, type: type, gym: dumbbellsOnly).exercises {
                XCTAssertTrue(equipmentById[item.exerciseId]!.isSubset(of: dumbbellsOnly), item.exerciseId)
            }
        }
    }

    func testMissingEquipmentIsReportedNotInvented() {
        let w = workout(minutes: 90, type: "pull", gym: dumbbellsOnly)
        XCTAssertTrue(w.skipped.map(\.name).contains("vertical_pull"))
    }

    func testSameInputsGiveSameWorkout() {
        let history = [session("2026-10-21", "push", "bench_press", 60, [8, 8, 7])]
        XCTAssertEqual(workout(minutes: 45, history: history, type: nil),
                       workout(minutes: 45, history: history, type: nil))
    }

    func testKeepsTheExerciseYouDidLastTime() {
        let history = [session("2026-10-21", "push", "db_bench_press", 24, [10, 10, 9])]
        XCTAssertEqual(workout(history: history).exercises.first?.exerciseId, "db_bench_press")
    }

    func testLegsDayPicksTwoDifferentKneeExercises() {
        let ids = workout(minutes: 90, type: "legs").exercises.map(\.exerciseId)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRotationFollowsPushPullLegs() {
        let push = Session(date: "2026-10-21", sessionType: "push", exercises: [])
        let legs = Session(date: "2026-10-25", sessionType: "legs", exercises: [])
        XCTAssertEqual(Engine.nextSessionType(catalog: catalog, history: []), "push")
        XCTAssertEqual(Engine.nextSessionType(catalog: catalog, history: [push]), "pull")
        XCTAssertEqual(Engine.nextSessionType(catalog: catalog, history: [legs]), "push")
    }

    // MARK: Progression

    func testFirstTimeHasNoWeightAndExplainsWhy() throws {
        let bench = try find(workout(), "bench_press")
        XCTAssertNil(bench.weight)
        XCTAssertTrue(bench.reason.contains("First time"))
    }

    func testTopOfRangeOnEverySetAddsWeight() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]),
                             "bench_press")
        XCTAssertEqual(bench.weight, 62.5)
        XCTAssertEqual(bench.targetReps, 6)
        XCTAssertEqual(bench.reason, "You hit 10 reps on every set last time: +2.5 kg.")
    }

    func testOtherwiseHoldsWeightAndAimsOneRepHigher() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [9, 8, 7])]),
                             "bench_press")
        XCTAssertEqual(bench.weight, 60)
        XCTAssertEqual(bench.targetReps, 8)
    }

    func testTwoMissesInARowDropsAboutTenPercent() throws {
        let history = [session("2026-10-17", "push", "bench_press", 60, [6, 5, 4]),
                       session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]
        XCTAssertEqual(try find(workout(history: history), "bench_press").weight, 52.5)
    }

    func testOneMissAloneDoesNotDeload() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]),
                             "bench_press")
        XCTAssertEqual(bench.weight, 60)
    }

    // MARK: Recovery

    func testLowRecoveryHoldsWeightAndCutsASet() throws {
        let history = [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]
        let bench = try find(workout(history: history, recovery: .low), "bench_press")
        XCTAssertEqual(bench.weight, 60)
        XCTAssertEqual(bench.sets, 2)
        XCTAssertTrue(bench.reason.contains("recovery is low"))
    }

    // MARK: Units

    func testPoundsProgressInPoundSteps() throws {
        let w = workout(history: [session("2026-10-21", "push", "bench_press", 135 * 0.45359237, [10, 10, 10])],
                        unit: .lb)
        let bench = try find(w, "bench_press")
        XCTAssertEqual(w.unit, .lb)
        XCTAssertEqual(bench.weight, 140)
        XCTAssertEqual(bench.increment, 5)
        XCTAssertEqual(bench.reason, "You hit 10 reps on every set last time: +5 lb.")
    }

    func testSwitchingUnitsSnapsToALoadableWeight() throws {
        // 60 kg = 132.28 lb
        let w = workout(history: [session("2026-10-21", "push", "bench_press", 60, [9, 8, 7])], unit: .lb)
        XCTAssertEqual(try find(w, "bench_press").weight, 130)
    }

    func testDeloadInPoundsRoundsDownToAPoundStep() throws {
        let history = [session("2026-10-17", "push", "bench_press", 135 * 0.45359237, [6, 5, 4]),
                       session("2026-10-21", "push", "bench_press", 135 * 0.45359237, [6, 5, 5])]
        XCTAssertEqual(try find(workout(history: history, unit: .lb), "bench_press").weight, 120)
    }

    // MARK: Changes and Undo

    func testIncreaseIsMarkedAndCanBeUndone() throws {
        let w = workout(history: [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])])
        let bench = try find(w, "bench_press")
        XCTAssertEqual(bench.change, .increased)
        XCTAssertEqual(bench.previousWeight, 60)
        let kept = try find(Engine.undoChange(w, exerciseId: "bench_press"), "bench_press")
        XCTAssertEqual(kept.weight, 60)
        XCTAssertEqual(kept.targetReps, 10)
        XCTAssertNil(kept.change)
        XCTAssertEqual(kept.reason, "Kept at 60 kg, as you asked. Aim for 10 reps.")
    }

    func testDeloadIsMarkedAndUndoAimsForTheBottomOfTheRange() throws {
        let history = [session("2026-10-17", "push", "bench_press", 60, [6, 5, 4]),
                       session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]
        let w = workout(history: history)
        XCTAssertEqual(try find(w, "bench_press").change, .deloaded)
        let kept = try find(Engine.undoChange(w, exerciseId: "bench_press"), "bench_press")
        XCTAssertEqual(kept.weight, 60)
        XCTAssertEqual(kept.targetReps, 6)
    }

    func testHoldingWeightIsNotAChange() throws {
        let held = [session("2026-10-21", "push", "bench_press", 60, [9, 8, 7])]
        let earned = [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]
        for w in [workout(history: held), workout(history: earned, recovery: .low), workout()] {
            XCTAssertNil(try find(w, "bench_press").change)
            XCTAssertEqual(Engine.undoChange(w, exerciseId: "bench_press"), w)
        }
    }

    // MARK: Time

    func testFitsInsideTheTimeAvailable() {
        for minutes in [20, 30, 45, 60] {
            XCTAssertLessThanOrEqual(workout(minutes: minutes).estimatedMinutes, minutes)
        }
    }

    func testPlentyOfTimeKeepsTheFullSession() {
        let w = workout(minutes: 90)
        XCTAssertEqual(w.exercises.count, 4)
        XCTAssertTrue(w.exercises.allSatisfy { $0.sets == 3 })
    }

    func testShortSessionTrimsSetsBeforeDroppingExercises() {
        let w = workout(minutes: 30)
        XCTAssertEqual(w.exercises.count, 4)
        XCTAssertTrue(w.exercises.contains { $0.sets == 2 })
    }
}
