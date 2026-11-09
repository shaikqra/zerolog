import XCTest
@testable import ZeroLogCore

/// Reproduces, on Linux, the exact flow the phone behaviour test walks:
/// a push workout with EVERY set at the top of the range, one pull session,
/// one legs session, then the next push plan. The behaviour suite keeps
/// reporting "no automatic change appeared" after this walk; this test asks
/// the engine the same question without a simulator in the way.
final class RotationChangeTests: XCTestCase {
    private var catalog: Catalog!

    override func setUpWithError() throws {
        catalog = try Catalog.bundled()
    }

    private func logged(_ workout: Workout, topOfRange: Bool, setsPerExercise: Int, date: String) -> Session {
        // Log sets exactly as the UI would: the first `setsPerExercise` sets
        // of the FIRST exercise, at its prescribed weight (or 20kg when the
        // engine says "pick a weight"), at the top of the range or at target.
        let first = workout.exercises[0]
        let weight = first.weight ?? 20
        let reps = topOfRange ? first.repRange[1] : first.targetReps
        let sets = (0..<setsPerExercise).map { _ in LoggedSet(weightKg: weight, reps: reps) }
        return Session(date: date, sessionType: workout.sessionType,
                       exercises: [LoggedExercise(exerciseId: first.exerciseId, sets: sets)])
    }

    func testRaiseEarnedOnPushSurvivesPullAndLegsDays() throws {
        let gym = Set(catalog.exercises.flatMap(\.equipment))
        var history: [Session] = []

        // W1: push, every set at the top of the range.
        let push1 = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                           minutes: 60, history: history)
        XCTAssertEqual(push1.sessionType, "push", "rotation should start at push")
        let benchId = push1.exercises[0].exerciseId
        history.append(logged(push1, topOfRange: true, setsPerExercise: 4, date: "2026-11-09"))

        // W2, W3: the rotation days, one ordinary set each.
        let pull = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                          minutes: 60, history: history)
        XCTAssertEqual(pull.sessionType, "pull")
        history.append(logged(pull, topOfRange: false, setsPerExercise: 1, date: "2026-11-09"))

        let legs = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                          minutes: 60, history: history)
        XCTAssertEqual(legs.sessionType, "legs")
        history.append(logged(legs, topOfRange: false, setsPerExercise: 1, date: "2026-11-09"))

        // Back to push: the raise earned on W1 must be here, marked.
        let push2 = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                           minutes: 60, history: history)
        XCTAssertEqual(push2.sessionType, "push")
        let bench = try XCTUnwrap(push2.exercises.first { $0.exerciseId == benchId },
                                  "the exercise that earned a raise vanished from the next push day")
        XCTAssertEqual(bench.change, .increased,
                       "every set hit the top of the range on W1; the next push plan must mark the raise. reason: \(bench.reason)")
    }
}
