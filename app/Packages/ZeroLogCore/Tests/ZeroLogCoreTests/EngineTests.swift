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
                         type: String? = "push", gym: Set<String>? = nil) -> Workout {
        Engine.generateWorkout(catalog: catalog, gymEquipment: gym ?? fullGym, minutes: minutes,
                               history: history, recovery: recovery, sessionType: type)
    }

    private func find(_ workout: Workout, _ id: String) throws -> PlannedExercise {
        try XCTUnwrap(workout.exercises.first { $0.exerciseId == id })
    }

    // MARK: Database

    func testDatabaseLoads() {
        XCTAssertEqual(catalog.exercises.count, 19)
        XCTAssertEqual(catalog.sessions["order"], ["push", "pull", "legs"])
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
        XCTAssertNil(bench.weightKg)
        XCTAssertTrue(bench.reason.contains("First time"))
    }

    func testTopOfRangeOnEverySetAddsWeight() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]),
                             "bench_press")
        XCTAssertEqual(bench.weightKg, 62.5)
        XCTAssertEqual(bench.targetReps, 6)
        XCTAssertEqual(bench.reason, "You hit 10 reps on every set last time: +2.5 kg.")
    }

    func testOtherwiseHoldsWeightAndAimsOneRepHigher() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [9, 8, 7])]),
                             "bench_press")
        XCTAssertEqual(bench.weightKg, 60)
        XCTAssertEqual(bench.targetReps, 8)
    }

    func testTwoMissesInARowDropsAboutTenPercent() throws {
        let history = [session("2026-10-17", "push", "bench_press", 60, [6, 5, 4]),
                       session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]
        XCTAssertEqual(try find(workout(history: history), "bench_press").weightKg, 52.5)
    }

    func testOneMissAloneDoesNotDeload() throws {
        let bench = try find(workout(history: [session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]),
                             "bench_press")
        XCTAssertEqual(bench.weightKg, 60)
    }

    // MARK: Recovery

    func testLowRecoveryHoldsWeightAndCutsASet() throws {
        let history = [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]
        let bench = try find(workout(history: history, recovery: .low), "bench_press")
        XCTAssertEqual(bench.weightKg, 60)
        XCTAssertEqual(bench.sets, 2)
        XCTAssertTrue(bench.reason.contains("recovery is low"))
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
