import XCTest
@testable import ZeroLogCore

/// Progress over time — the reason to open the app on a rest day.
///
/// The tests worth having are about honesty: not claiming a trend from one
/// session, not calling a repeat a record, and agreeing with the planner about
/// what "your working weight" means.
final class ExerciseProgressTests: XCTestCase {

    private func session(_ date: String, _ sets: [(Double, Int)],
                         id: String = "bench_press") -> Session {
        Session(date: date, sessionType: "push", exercises: [
            LoggedExercise(exerciseId: id,
                           sets: sets.map { LoggedSet(weightKg: $0.0, reps: $0.1) }),
        ])
    }

    private func progress(_ history: [Session]) -> ExerciseProgress {
        Engine.progress(for: "bench_press", name: "Barbell bench press",
                        history: history, unit: .kg, step: 2.5)
    }

    func testPointsComeBackOldestFirst() {
        let p = progress([session("2026-10-01", [(60, 8)]),
                          session("2026-10-08", [(62.5, 8)]),
                          session("2026-10-15", [(65, 8)])])
        XCTAssertEqual(p.points.map(\.date),
                       ["2026-10-01", "2026-10-08", "2026-10-15"])
        XCTAssertEqual(p.points.map(\.workingWeight), [60, 62.5, 65])
    }

    /// The progress screen and the planner must agree on "working weight",
    /// or one of them is lying to the user.
    func testWorkingWeightMatchesWhatThePlannerUses() {
        let sets = [LoggedSet(weightKg: 60, reps: 8), LoggedSet(weightKg: 65, reps: 5)]
        let p = progress([Session(date: "2026-10-01", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: sets),
        ])])
        let plannerView = Engine.workingWeight(Engine.inUnit(sets, unit: .kg, step: 2.5))
        XCTAssertEqual(p.points.first?.workingWeight, plannerView)
    }

    func testBestRepsAreTakenAtTheWorkingWeight() {
        let p = progress([session("2026-10-01", [(60, 10), (60, 8), (50, 15)])])
        XCTAssertEqual(p.points.first?.workingWeight, 60)
        XCTAssertEqual(p.points.first?.bestReps, 10, "the 15 reps were at a lighter weight")
    }

    func testVolumeCountsEverySet() {
        let p = progress([session("2026-10-01", [(60, 10), (60, 8)])])
        XCTAssertEqual(p.points.first?.volume, 60 * 10 + 60 * 8)
        XCTAssertEqual(p.points.first?.sets, 2)
    }

    // MARK: - Records

    func testFirstSessionIsARecord() {
        let p = progress([session("2026-10-01", [(60, 8)])])
        XCTAssertEqual(p.points.first?.isRecord, true)
    }

    /// Repeating your best is not a new best. Calling it one would cheapen the
    /// real thing and make the marker meaningless.
    func testRepeatingYourBestIsNotARecord() {
        let p = progress([session("2026-10-01", [(60, 8)]),
                          session("2026-10-08", [(60, 10)])])
        XCTAssertEqual(p.points.map(\.isRecord), [true, false])
    }

    func testGoingBackDownIsNotARecord() {
        let p = progress([session("2026-10-01", [(60, 8)]),
                          session("2026-10-08", [(65, 8)]),
                          session("2026-10-15", [(60, 8)])])
        XCTAssertEqual(p.points.map(\.isRecord), [true, true, false])
        XCTAssertEqual(p.heaviest, 65, "the best stands even after a lighter day")
    }

    // MARK: - Not claiming a trend that does not exist

    /// One session is not a trend. Showing "+0 kg" on day one implies a lack of
    /// progress that has not had the chance to happen.
    func testOneSessionReportsNoChangeAtAll() {
        let p = progress([session("2026-10-01", [(60, 8)])])
        XCTAssertNil(p.changeSinceStart)
        XCTAssertFalse(p.hasTrend)
    }

    func testTwoSessionsGiveARealChange() {
        let p = progress([session("2026-10-01", [(60, 8)]),
                          session("2026-10-08", [(65, 8)])])
        XCTAssertTrue(p.hasTrend)
        XCTAssertEqual(p.changeSinceStart, 5)
    }

    /// A drop is reported plainly as a drop, in both directions, without
    /// comment. The no-shaming rule covers implication as well as wording.
    func testADropIsReportedHonestly() {
        let p = progress([session("2026-10-01", [(70, 8)]),
                          session("2026-10-08", [(65, 8)])])
        XCTAssertEqual(p.changeSinceStart, -5)
    }

    func testNoHistoryIsEmptyNotZero() {
        let p = progress([])
        XCTAssertTrue(p.points.isEmpty)
        XCTAssertNil(p.changeSinceStart)
        XCTAssertNil(p.latest)
        XCTAssertEqual(p.heaviest, 0)
    }

    func testOtherExercisesAreIgnored() {
        let mixed = [Session(date: "2026-10-01", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 60, reps: 8)]),
            LoggedExercise(exerciseId: "overhead_press", sets: [LoggedSet(weightKg: 40, reps: 8)]),
        ])]
        let p = progress(mixed)
        XCTAssertEqual(p.points.count, 1)
        XCTAssertEqual(p.points.first?.workingWeight, 60)
    }

    func testSkippedExercisesLeaveNoPoint() {
        let withEmpty = [Session(date: "2026-10-01", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: []),
        ])]
        XCTAssertTrue(progress(withEmpty).points.isEmpty,
                      "an exercise you skipped is not a data point")
    }

    // MARK: - The list of what to show

    func testTrainedExercisesAreMostRecentFirstAndUnique() throws {
        let catalog = try Catalog.bundled()
        let history = [
            session("2026-10-01", [(60, 8)], id: "bench_press"),
            session("2026-10-05", [(40, 8)], id: "overhead_press"),
            session("2026-10-09", [(62.5, 8)], id: "bench_press"),
        ]
        let trained = Engine.trainedExercises(history: history, catalog: catalog)
        XCTAssertEqual(trained.map(\.id), ["bench_press", "overhead_press"],
                       "most recently trained first, each listed once")
    }

    func testUntrainedExercisesAreNotListed() throws {
        let catalog = try Catalog.bundled()
        let trained = Engine.trainedExercises(history: [], catalog: catalog)
        XCTAssertTrue(trained.isEmpty, "the list is the user's, not the catalog's")
    }
}
