import XCTest
@testable import ZeroLogCore

/// The three things the founder found missing after using the app for the first
/// time: a timer between sets, any sense of what is coming next, and any sign
/// that anything is improving.
final class RestAndProgressTests: XCTestCase {

    // MARK: - Rest timer

    func testRestLengthMatchesTheTableUsedForTimeEstimates() {
        // If these drift apart, the clock disagrees with "about 38 minutes" on
        // the plan, and one of the two numbers is lying.
        XCTAssertEqual(RestTimer.suggestedSeconds(kind: "compound"),
                       Engine.restSeconds["compound"])
        XCTAssertEqual(RestTimer.suggestedSeconds(kind: "isolation"),
                       Engine.restSeconds["isolation"])
    }

    /// An unknown movement must not be told to rest for zero seconds.
    func testUnknownKindFallsBackToAUsefulRest() {
        XCTAssertEqual(RestTimer.suggestedSeconds(kind: "nonsense"), 90)
        XCTAssertGreaterThan(RestTimer.suggestedSeconds(kind: ""), 0)
    }

    func testCountdownReadsCorrectlyAndStopsAtReady() {
        let advice = RestTimer.advice(kind: "compound", secondsSinceSet: 0)
        XCTAssertEqual(advice.suggestedSeconds, 150)
        XCTAssertEqual(advice.display, "2:30")
        XCTAssertFalse(advice.isReady)
        XCTAssertEqual(advice.progress, 0, accuracy: 0.001)

        XCTAssertEqual(RestTimer.advice(kind: "compound", secondsSinceSet: 90).display, "1:00")
        XCTAssertEqual(RestTimer.advice(kind: "compound", secondsSinceSet: 145).display, "0:05")

        let done = RestTimer.advice(kind: "compound", secondsSinceSet: 150)
        XCTAssertTrue(done.isReady)
        XCTAssertEqual(done.display, "Ready")
        XCTAssertEqual(done.progress, 1, accuracy: 0.001)
    }

    /// A clock that runs past the target, or a timestamp from the future, must
    /// not produce a negative countdown or a progress ring past full.
    func testTimerNeverGoesNegativeOrOverfull() {
        let over = RestTimer.advice(kind: "isolation", secondsSinceSet: 10_000)
        XCTAssertEqual(over.remainingSeconds, 0)
        XCTAssertEqual(over.display, "Ready")
        XCTAssertEqual(over.progress, 1, accuracy: 0.001)

        let negative = RestTimer.advice(kind: "isolation", secondsSinceSet: -50)
        XCTAssertEqual(negative.elapsedSeconds, 0)
        XCTAssertFalse(negative.isReady)
        XCTAssertGreaterThanOrEqual(negative.progress, 0)
    }

    /// Non-negotiable product rule: no cheerleading, anywhere. A timer is the
    /// easiest place to let one in.
    func testTimerTextDoesNotCheerlead() {
        let banned = ["great", "awesome", "crush", "beast", "let's go", "keep it up",
                      "well done", "smash", "don't stop", "come on"]
        for seconds in [0, 30, 90, 150, 400] {
            for kind in ["compound", "isolation"] {
                let advice = RestTimer.advice(kind: kind, secondsSinceSet: seconds)
                let text = (advice.display + " " + advice.caption).lowercased()
                for word in banned {
                    XCTAssertFalse(text.contains(word), "timer said \"\(text)\"")
                }
            }
        }
    }

    func testPlannedExercisesExposeTheirOwnRestLength() throws {
        let catalog = try Catalog.bundled()
        let plan = Engine.generateWorkout(catalog: catalog,
                                          gymEquipment: ["barbell", "rack", "bench", "dumbbells"],
                                          minutes: 45, history: [])
        XCTAssertFalse(plan.exercises.isEmpty)
        for exercise in plan.exercises {
            XCTAssertGreaterThan(exercise.restSeconds, 0,
                                 "\(exercise.name) has no rest length")
        }
    }

    // MARK: - What is coming next

    /// Order, never dates. The app has never asked which days the user trains,
    /// so naming a day would be inventing a schedule they never set.
    func testUpcomingFollowsTheRotationFromWhereHistoryLeftOff() throws {
        let catalog = try Catalog.bundled()
        let order = try XCTUnwrap(catalog.sessions["order"])
        XCTAssertGreaterThanOrEqual(order.count, 3)

        let fresh = Engine.upcoming(catalog: catalog, history: [], count: 3)
        XCTAssertEqual(fresh.map(\.sessionType), Array(order.prefix(3)))
        XCTAssertEqual(fresh.map(\.position), [0, 1, 2])

        let afterFirst = [Session(date: "2026-11-01", sessionType: order[0], exercises: [])]
        let next = Engine.upcoming(catalog: catalog, history: afterFirst, count: 3)
        XCTAssertEqual(next.first?.sessionType, order[1],
                       "after \(order[0]) the next session should be \(order[1])")
    }

    func testUpcomingWrapsAroundAndHandlesSillyCounts() throws {
        let catalog = try Catalog.bundled()
        let order = try XCTUnwrap(catalog.sessions["order"])
        let many = Engine.upcoming(catalog: catalog, history: [], count: order.count + 2)
        XCTAssertEqual(many.count, order.count + 2)
        XCTAssertEqual(many[order.count].sessionType, order[0], "rotation should wrap")
        XCTAssertTrue(Engine.upcoming(catalog: catalog, history: [], count: 0).isEmpty)
    }

    // MARK: - Progress

    private func session(_ date: String, _ type: String,
                         sets: [(Int, Double)]) -> Session {
        Session(date: date, sessionType: type, exercises: [
            LoggedExercise(exerciseId: "bb_bench",
                           sets: sets.map { LoggedSet(weightKg: $0.1, reps: $0.0) })
        ])
    }

    func testSummaryCountsOnlyThisWeekAndComparesToLast() {
        // ISO weeks run Monday-Sunday. 2026-11-09 is a Monday.
        let history = [
            session("2026-11-02", "push", sets: [(10, 50), (10, 50)]),   // last week
            session("2026-11-09", "push", sets: [(10, 60), (10, 60)]),   // this week
            session("2026-11-11", "pull", sets: [(8, 40)]),              // this week
        ]
        let summary = Progress.summary(history: history, today: "2026-11-13")

        XCTAssertEqual(summary.workoutsThisWeek, 2)
        XCTAssertEqual(summary.setsThisWeek, 3)
        // Bound the arithmetic to Double first. Left inline, the literals make
        // the type checker explore every numeric overload and it gives up.
        let expectedThis: Double = 1520   // 10x60 + 10x60 + 8x40
        let expectedLast: Double = 1000   // 10x50 + 10x50
        XCTAssertEqual(summary.volumeThisWeek, expectedThis, accuracy: 0.001)
        XCTAssertEqual(summary.volumeLastWeek, expectedLast, accuracy: 0.001)

        let change = summary.volumeChangePercent ?? 0
        XCTAssertEqual(change, 52.0, accuracy: 0.5)
    }

    /// A first week has nothing to compare against. That must read as "no
    /// comparison", NOT as zero change -- showing "0%" to someone who just
    /// started is both wrong and quietly discouraging.
    func testFirstWeekHasNoPercentageRatherThanZero() {
        let history = [session("2026-11-09", "push", sets: [(10, 60)])]
        let summary = Progress.summary(history: history, today: "2026-11-09")
        XCTAssertEqual(summary.setsThisWeek, 1)
        XCTAssertNil(summary.volumeChangePercent)
        XCTAssertTrue(summary.hasAnything)
    }

    func testEmptyHistoryIsAllZeroAndShowsNothing() {
        let summary = Progress.summary(history: [], today: "2026-11-09")
        XCTAssertEqual(summary.workoutsThisWeek, 0)
        XCTAssertEqual(summary.setsThisWeek, 0)
        XCTAssertNil(summary.volumeChangePercent)
        XCTAssertFalse(summary.hasAnything, "a fresh install should show no progress card")
    }

    /// A malformed date must not crash or silently land in the current week.
    func testUnparseableDatesAreIgnoredNotCounted() {
        let history = [
            session("not-a-date", "push", sets: [(10, 100)]),
            session("2026-11-09", "push", sets: [(5, 20)]),
        ]
        let summary = Progress.summary(history: history, today: "2026-11-09")
        XCTAssertEqual(summary.workoutsThisWeek, 1)
        XCTAssertEqual(summary.volumeThisWeek, 100, accuracy: 0.001)
    }

    /// The same history must summarise identically regardless of device locale
    /// or time zone, or two phones disagree about the same training week.
    func testWeekBoundariesAreFixedNotLocaleDependent() {
        let history = [
            session("2026-11-08", "push", sets: [(10, 10)]),  // Sunday, previous week
            session("2026-11-09", "pull", sets: [(10, 10)]),  // Monday, this week
        ]
        let summary = Progress.summary(history: history, today: "2026-11-12")
        XCTAssertEqual(summary.workoutsThisWeek, 1,
                       "Sunday the 8th belongs to the previous ISO week")
        XCTAssertEqual(summary.volumeLastWeek, 100, accuracy: 0.001)
    }
}
