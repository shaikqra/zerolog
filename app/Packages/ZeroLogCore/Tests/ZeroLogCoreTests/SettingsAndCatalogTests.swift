import XCTest
@testable import ZeroLogCore

/// Guards the two bugs fixed together: the watch inventing a gym, and the gaps
/// in the exercise database.
final class SettingsAndCatalogTests: XCTestCase {

    private func catalog() throws -> Catalog { try Catalog.bundled() }

    private func tempStore() throws -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-settings-\(UUID().uuidString).json")
        return SettingsStore(fileURL: url)
    }

    // MARK: - The watch must not invent a gym

    /// The original bug: the watch planned from a hardcoded sample gym containing
    /// every machine, so a dumbbells-only user was shown barbell bench press with
    /// no sign the equipment list was made up. A confident wrong plan is worse
    /// than no plan.
    func testNoSettingsProducesAnHonestMessageNotAGuessedWorkout() throws {
        let outcome = PlanRequest.resolve(catalog: try catalog(), settings: nil,
                                          history: [], isWatch: true)
        guard case .needsSetup(let message) = outcome else {
            return XCTFail("a watch with no synced settings must not produce a workout")
        }
        XCTAssertTrue(message.lowercased().contains("phone"),
                      "the watch should say where to go to fix it, got: \\(message)")
    }

    func testEmptyEquipmentIsTreatedAsNotSetUp() throws {
        let settings = UserSettings(equipment: [], minutes: 45, unit: .kg)
        let outcome = PlanRequest.resolve(catalog: try catalog(), settings: settings, history: [])
        guard case .needsSetup = outcome else {
            return XCTFail("no equipment cannot yield a workout")
        }
    }

    /// The actual fix: the plan has to come from the user's own gym and their own
    /// session length, not 45 minutes and every machine in the building.
    func testPlanUsesTheUsersOwnEquipmentAndSessionLength() throws {
        let cat = try catalog()
        let settings = UserSettings(equipment: ["dumbbells", "bench"], minutes: 30, unit: .lb)
        guard case .ready(let workout) = PlanRequest.resolve(catalog: cat, settings: settings,
                                                             history: []) else {
            return XCTFail("a dumbbells-and-bench gym should still yield a workout")
        }
        XCTAssertLessThanOrEqual(workout.estimatedMinutes, 30, "must respect the user's 30 minutes")
        XCTAssertEqual(workout.unit, .lb, "must respect the user's unit")

        let owned: Set<String> = ["dumbbells", "bench"]
        for planned in workout.exercises {
            let exercise = cat.exercises.first { $0.id == planned.exerciseId }
            XCTAssertNotNil(exercise)
            XCTAssertTrue(Set(exercise!.equipment).isSubset(of: owned),
                          "\\(planned.name) needs equipment this gym does not have")
        }
    }

    func testSettingsSurviveASaveAndLoadAndStartAbsent() throws {
        let store = try tempStore()
        XCTAssertNil(try store.load(), "a fresh device is not set up, which is not the same as empty")
        let settings = UserSettings(equipment: ["barbell", "rack"], minutes: 60, unit: .kg)
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
    }

    // MARK: - Exercise database gaps

    /// Before this fix `vertical_pull` contained only the lat pulldown, so a gym
    /// without that one machine silently lost a whole movement from pull day.
    func testEveryMovementSlotHasMoreThanOneOption() throws {
        let cat = try catalog()
        var slots: Set<String> = []
        for (key, patterns) in cat.sessions where key != "order" { slots.formUnion(patterns) }
        for pattern in slots {
            let count = cat.exercises.filter { $0.pattern == pattern }.count
            XCTAssertGreaterThan(count, 1,
                                 "\\(pattern) has \\(count) exercise(s); one piece of missing kit "
                                 + "would delete this movement from the session")
        }
    }

    func testPullUpExists() throws {
        XCTAssertNotNil(try catalog().exercises.first { $0.id == "pull_up" },
                        "a lifting app without a pull-up is not credible")
    }

    func testLegDayCoversCalvesAndCoreNotTheSamePatternTwice() throws {
        let legs = try catalog().sessions["legs"] ?? []
        XCTAssertTrue(legs.contains("calf_raise"), "leg day had no calf work")
        XCTAssertTrue(legs.contains("core_flexion"), "the database had no core movements at all")
    }

    /// At least one core option must need no equipment, or home lifters get an
    /// empty slot.
    func testSomeCoreWorkNeedsNoEquipment() throws {
        let core = try catalog().exercises.filter { $0.pattern == "core_flexion" }
        XCTAssertTrue(core.contains { $0.equipment.isEmpty },
                      "core work should be possible with no kit at all")
    }

    // MARK: - Rep profiles must line up with the counter

    /// A typo here would silently fall back to the generic profile and quietly
    /// cost accuracy, with nothing failing.
    func testEveryRepProfileNamesARealCalibration() throws {
        for ex in try catalog().exercises {
            guard let key = ex.repProfile else { continue }
            XCTAssertNotNil(RepCounter.profiles[key],
                            "\\(ex.id) points at rep profile '\\(key)', which RepCounter does not define")
        }
    }

    /// Squats were marked not-detectable by assumption. MM-Fit measured 86%
    /// within +/-1 on held-out athletes, so the flag was simply wrong.
    func testSquatsAreMarkedDetectableBecauseTheDataSaysSo() throws {
        let squat = try catalog().exercises.first { $0.id == "back_squat" }
        XCTAssertEqual(squat?.detectable, true)
        XCTAssertEqual(squat?.repProfile, "squats")
        // MM-Fit squats were BODYWEIGHT. A loaded barbell squat is slower and the
        // wrist is braced against the bar, so this transfer is untested.
        XCTAssertEqual(squat?.hasVerifiedRepProfile, false,
                       "a loaded back squat was never in the validation set; do not claim it was")
    }

    /// Seated machine work keeps the wrist still, so it cannot be counted from
    /// the wrist. Claiming otherwise would log silent wrong numbers.
    func testSeatedMachineWorkIsNotClaimedAsDetectable() throws {
        let legPress = try catalog().exercises.first { $0.id == "leg_press" }
        XCTAssertEqual(legPress?.detectable, false)
        let hanging = try catalog().exercises.first { $0.id == "hanging_knee_raise" }
        XCTAssertEqual(hanging?.detectable, false,
                       "the hands grip a fixed bar, so the wrist barely moves")
    }

    /// Only movements actually present in MM-Fit may claim a verified profile.
    func testVerifiedProfilesAreOnlyTheMovementsWeActuallyTested() throws {
        let measured: Set<String> = ["dumbbell_shoulder_press", "lateral_shoulder_raises",
                                      "dumbbell_rows", "bicep_curls", "tricep_extensions",
                                      "squats", "situps", "pushups", "lunges", "jumping_jacks"]
        for ex in try catalog().exercises where ex.hasVerifiedRepProfile {
            guard let key = ex.repProfile else {
                return XCTFail("\\(ex.id) claims a verified profile but names none")
            }
            XCTAssertTrue(measured.contains(key),
                          "\\(ex.id) claims verification against '\\(key)', which was not in MM-Fit")
        }
    }

    /// The planner has to carry the profile through, or the watch cannot use the
    /// calibration when it logs the set.
    func testPlannedExerciseCarriesTheRepProfile() throws {
        let cat = try catalog()
        let settings = UserSettings(equipment: ["dumbbells", "bench"], minutes: 90, unit: .kg)
        guard case .ready(let workout) = PlanRequest.resolve(catalog: cat, settings: settings,
                                                             history: []) else {
            return XCTFail("expected a workout")
        }
        for planned in workout.exercises {
            let source = cat.exercises.first { $0.id == planned.exerciseId }
            XCTAssertEqual(planned.repProfile, source?.repProfile,
                           "\\(planned.name) lost its calibration on the way into the plan")
        }
    }
}
