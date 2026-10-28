import XCTest
@testable import ZeroLogCore

final class ActiveWorkoutTests: XCTestCase {
    private var catalog: Catalog!
    private let gym: Set<String> = ["barbell", "bench", "rack", "dumbbells", "cable", "lat_pulldown", "leg_press"]

    override func setUpWithError() throws {
        catalog = try Catalog.bundled()
    }

    private func pushPlan(history: [Session] = [], unit: WeightUnit = .kg) -> Workout {
        Engine.generateWorkout(catalog: catalog, gymEquipment: gym, minutes: 90, history: history,
                               sessionType: "push", unit: unit)
    }

    func testWalksThroughSetsThenExercisesInOrder() {
        var w = ActiveWorkout(plan: pushPlan(), date: "2026-10-28")
        XCTAssertEqual(w.current?.exerciseId, "bench_press")
        XCTAssertEqual(w.setNumber, 1)
        w.confirmSet(weight: 50, reps: 8)
        XCTAssertEqual(w.setNumber, 2)
        w.confirmSet(weight: 50, reps: 8)
        w.confirmSet(weight: 50, reps: 7)
        XCTAssertEqual(w.current?.exerciseId, "overhead_press")
        XCTAssertEqual(w.setNumber, 1)
        XCTAssertEqual(w.logged, [LoggedExercise(exerciseId: "bench_press", sets: [
            LoggedSet(weightKg: 50, reps: 8), LoggedSet(weightKg: 50, reps: 8), LoggedSet(weightKg: 50, reps: 7),
        ])])
    }

    func testFirstSetIsPrefilledFromThePlanThenFromWhatYouJustDid() {
        let history = [Session(date: "2026-10-21", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 60, reps: 8)]),
        ])]
        var w = ActiveWorkout(plan: pushPlan(history: history), date: "2026-10-28")
        XCTAssertEqual(w.suggestedWeight, 60)
        XCTAssertEqual(w.suggestedReps, 9)  // did 8 last time, so the engine asks for one more
        w.confirmSet(weight: 57.5, reps: 7)
        XCTAssertEqual(w.suggestedWeight, 57.5)
        XCTAssertEqual(w.suggestedReps, 7)
    }

    func testFirstTimeExerciseHasNoSuggestedWeight() {
        XCTAssertNil(ActiveWorkout(plan: pushPlan(), date: "2026-10-28").suggestedWeight)
    }

    func testImpossibleValuesAreRejected() {
        var w = ActiveWorkout(plan: pushPlan(), date: "2026-10-28")
        XCTAssertFalse(w.confirmSet(weight: 50, reps: 0))
        XCTAssertFalse(w.confirmSet(weight: -5, reps: 8))
        XCTAssertEqual(w.totalSetsLogged, 0)
        XCTAssertEqual(w.setNumber, 1)
    }

    func testSkippedExerciseIsLeftOutOfHistory() {
        var w = ActiveWorkout(plan: pushPlan(), date: "2026-10-28")
        w.skipExercise()
        XCTAssertEqual(w.current?.exerciseId, "overhead_press")
        w.confirmSet(weight: 30, reps: 8)
        XCTAssertEqual(w.session.exercises.map(\.exerciseId), ["overhead_press"])
    }

    func testEndingEarlyKeepsConfirmedSets() {
        var w = ActiveWorkout(plan: pushPlan(), date: "2026-10-28")
        w.confirmSet(weight: 50, reps: 8)
        w.endEarly()
        XCTAssertTrue(w.isFinished)
        XCTAssertNil(w.current)
        XCTAssertEqual(w.totalSetsLogged, 1)
        XCTAssertFalse(w.confirmSet(weight: 50, reps: 8))
    }

    /// The whole loop: log a workout, feed it back, and the next plan progresses from it.
    func testLoggedSessionDrivesNextWorkout() throws {
        var w = ActiveWorkout(plan: pushPlan(), date: "2026-10-28")
        for _ in 1...3 { w.confirmSet(weight: 50, reps: 10) }
        XCTAssertEqual(w.session.sessionType, "push")
        let next = pushPlan(history: [w.session])
        let bench = try XCTUnwrap(next.exercises.first { $0.exerciseId == "bench_press" })
        XCTAssertEqual(bench.weight, 52.5)
    }

    func testPoundsAreSavedAsKilogramsAndComeBackExact() {
        var w = ActiveWorkout(plan: pushPlan(unit: .lb), date: "2026-10-28")
        w.confirmSet(weight: 135, reps: 8)
        XCTAssertEqual(w.logged[0].sets[0].weightKg, 61.235, accuracy: 0.001)
        XCTAssertEqual(w.suggestedWeight, 135)
    }

    func testLoggedPoundsDriveNextWorkoutInPounds() throws {
        var w = ActiveWorkout(plan: pushPlan(unit: .lb), date: "2026-10-28")
        for _ in 1...3 { w.confirmSet(weight: 135, reps: 10) }
        let next = pushPlan(history: [w.session], unit: .lb)
        let bench = try XCTUnwrap(next.exercises.first { $0.exerciseId == "bench_press" })
        XCTAssertEqual(bench.weight, 140)
    }
}

final class HistoryStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func session(_ date: String) -> Session {
        Session(date: date, sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 60, reps: 8)]),
        ])
    }

    func testNoFileMeansNoHistory() throws {
        XCTAssertEqual(try HistoryStore(fileURL: url).load(), [])
    }

    func testSavedSessionsComeBackOldestFirst() throws {
        let store = HistoryStore(fileURL: url)
        try store.append(session("2026-10-21"))
        try store.append(session("2026-10-28"))
        XCTAssertEqual(try store.load().map(\.date), ["2026-10-21", "2026-10-28"])
    }

    func testDamagedFileIsNeverOverwritten() throws {
        try Data("not json".utf8).write(to: url)
        let store = HistoryStore(fileURL: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.append(session("2026-10-28")))
        XCTAssertEqual(try Data(contentsOf: url), Data("not json".utf8))
    }
}
