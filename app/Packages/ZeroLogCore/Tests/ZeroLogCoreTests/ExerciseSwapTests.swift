import XCTest
@testable import ZeroLogCore

/// Swapping an exercise when the rack is taken.
///
/// The tests that matter are the refusals: a substitute must never inherit the
/// previous exercise's weight, and must never absorb sets that were already
/// logged against something else.
final class ExerciseSwapTests: XCTestCase {

    private var catalog: Catalog { try! Catalog.bundled() }

    private var fullGym: Set<String> {
        Set(catalog.exercises.flatMap(\.equipment))
    }

    // MARK: - Finding alternatives

    func testAlternativesTrainTheSameMovementPattern() {
        let alts = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                             equipment: fullGym)
        XCTAssertFalse(alts.isEmpty, "a bench press must have some substitute")
        let benchPattern = catalog.exercise(id: "bench_press")!.pattern
        for alt in alts {
            XCTAssertEqual(alt.pattern, benchPattern,
                           "\(alt.id) is not the same movement as a bench press")
        }
    }

    func testTheExerciseNeverOffersItself() {
        let alts = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                             equipment: fullGym)
        XCTAssertFalse(alts.contains { $0.id == "bench_press" })
    }

    /// The point of the feature: the machine is taken, so only suggest things
    /// this gym actually has.
    func testEquipmentYouDoNotHaveIsNeverSuggested() {
        let minimal: Set<String> = ["barbell", "rack", "bench"]
        let alts = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                             equipment: minimal)
        for alt in alts {
            XCTAssertTrue(Set(alt.equipment).isSubset(of: minimal),
                          "\(alt.id) needs \(alt.equipment), which this gym lacks")
        }
    }

    /// Suggesting something already in today's session would quietly halve the
    /// workout's coverage while looking helpful.
    func testExercisesAlreadyInTodaysWorkoutAreExcluded() {
        let all = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                            equipment: fullGym)
        guard let first = all.first else { return XCTFail("need an alternative to exclude") }
        let filtered = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                                 equipment: fullGym,
                                                 excluding: [first.id])
        XCTAssertFalse(filtered.contains { $0.id == first.id })
    }

    func testSameKindIsOfferedBeforeADifferentKind() {
        let benchKind = catalog.exercise(id: "bench_press")!.kind
        let alts = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                             equipment: fullGym)
        let kinds = alts.map(\.kind)
        if let firstDifferent = kinds.firstIndex(where: { $0 != benchKind }) {
            let afterwards = kinds[firstDifferent...]
            XCTAssertFalse(afterwards.contains(benchKind),
                           "same-kind substitutes must all come first")
        }
    }

    func testUnknownExerciseYieldsNothingRatherThanCrashing() {
        XCTAssertTrue(ExerciseSwap.alternatives(to: "not_a_real_exercise",
                                                catalog: catalog,
                                                equipment: fullGym).isEmpty)
    }

    // MARK: - The weight must NOT carry over

    /// Benching 80 kg does not mean you dumbbell press 80 kg. Inheriting the
    /// number would put a dangerous suggestion in front of someone mid-session.
    func testASubstituteWithNoHistoryAsksForAWeightInsteadOfInheritingOne() {
        let history = [Session(date: "2026-10-28", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press",
                           sets: [LoggedSet(weightKg: 80, reps: 8)]),
        ])]
        guard let alt = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                                  equipment: fullGym).first else {
            return XCTFail("need an alternative")
        }
        let planned = ExerciseSwap.plan(alt, history: history, unit: .kg)
        XCTAssertNotEqual(planned.weight, 80,
                          "the previous exercise's weight must never carry across")
        XCTAssertEqual(planned.exerciseId, alt.id)
    }

    /// And when the substitute DOES have history, it uses its own.
    func testASubstituteUsesItsOwnHistory() {
        guard let alt = ExerciseSwap.alternatives(to: "bench_press", catalog: catalog,
                                                  equipment: fullGym).first else {
            return XCTFail("need an alternative")
        }
        let history = [Session(date: "2026-10-28", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 80, reps: 8)]),
            LoggedExercise(exerciseId: alt.id, sets: [LoggedSet(weightKg: 30, reps: 8),
                                                      LoggedSet(weightKg: 30, reps: 8)]),
        ])]
        let planned = ExerciseSwap.plan(alt, history: history, unit: .kg)
        XCTAssertEqual(planned.previousWeight, 30, "its own last working weight")
    }

    // MARK: - Swapping inside a live workout

    private func pushWorkout() -> ActiveWorkout {
        let plan = Engine.generateWorkout(catalog: catalog, gymEquipment: fullGym,
                                          minutes: 60, history: [], sessionType: "push")
        return ActiveWorkout(plan: plan, date: "2026-11-04")
    }

    func testSwappingReplacesTheExerciseAndResetsToSetOne() {
        var w = pushWorkout()
        guard let original = w.current else { return XCTFail("no exercise") }
        guard let alt = ExerciseSwap.alternatives(to: original.exerciseId, catalog: catalog,
                                                  equipment: fullGym).first else {
            return XCTFail("need an alternative")
        }
        let replacement = ExerciseSwap.plan(alt, history: [], unit: .kg)
        XCTAssertTrue(w.swapCurrentExercise(for: replacement))
        XCTAssertEqual(w.current?.exerciseId, alt.id)
        XCTAssertEqual(w.setNumber, 1)
    }

    /// The refusal that protects the record.
    func testSwappingIsRefusedOnceSetsAreLogged() {
        var w = pushWorkout()
        guard let original = w.current else { return XCTFail("no exercise") }
        w.confirmSet(weight: 60, reps: 8)
        guard let alt = ExerciseSwap.alternatives(to: original.exerciseId, catalog: catalog,
                                                  equipment: fullGym).first else {
            return XCTFail("need an alternative")
        }
        let replacement = ExerciseSwap.plan(alt, history: [], unit: .kg)
        XCTAssertFalse(w.swapCurrentExercise(for: replacement),
                       "a logged set must not be reassigned to a different movement")
        XCTAssertEqual(w.current?.exerciseId, original.exerciseId, "nothing changed")
        XCTAssertEqual(w.totalSetsLogged, 1, "and the set survives")
    }

    func testSwappingDoesNotDisturbTheRestOfThePlan() {
        var w = pushWorkout()
        let before = w.plan.exercises.map(\.exerciseId)
        guard let original = w.current,
              let alt = ExerciseSwap.alternatives(to: original.exerciseId, catalog: catalog,
                                                  equipment: fullGym).first else { return }
        w.swapCurrentExercise(for: ExerciseSwap.plan(alt, history: [], unit: .kg))
        let after = w.plan.exercises.map(\.exerciseId)
        XCTAssertEqual(before.count, after.count, "the session keeps its shape")
        XCTAssertEqual(Array(before.dropFirst()), Array(after.dropFirst()),
                       "only the current exercise changes")
    }
}
