import XCTest
@testable import ZeroLogCore

/// Day one. Before this, every exercise on a first session said "pick a weight
/// you can lift for 8-12 reps" -- four or five typed guesses, in an app whose
/// promise is that the user never types anything.
///
/// The safety asymmetry drives most of these assertions: starting too light
/// costs one easy session, starting too heavy risks injury on an unfamiliar
/// movement. Every test below prefers the light direction.
final class StartingWeightTests: XCTestCase {

    private func exercise(_ id: String) throws -> Exercise {
        let catalog = try Catalog.bundled()
        return try XCTUnwrap(catalog.exercises.first { $0.id == id }, "no exercise \(id)")
    }

    func testSuggestsALoadableOpeningWeightForABarbellLift() throws {
        let bench = try exercise("bench_press")
        let weight = try XCTUnwrap(StartingWeight.suggest(
            for: bench, bodyweightKg: 80, experience: .novice, unit: .kg))

        XCTAssertGreaterThanOrEqual(weight, 20, "never below an empty barbell")
        XCTAssertLessThan(weight, 80, "a novice should not open at bodyweight on bench")
        XCTAssertEqual(weight.truncatingRemainder(dividingBy: bench.increment(in: .kg)), 0,
                       accuracy: 0.001, "\(weight) kg cannot be loaded with 2.5 kg plates")
    }

    /// Without a bodyweight there is no basis, so the app must ASK rather than
    /// invent. A guess dressed as a suggestion is worse than a question.
    func testNoBodyweightMeansNoSuggestion() throws {
        let bench = try exercise("bench_press")
        XCTAssertNil(StartingWeight.suggest(for: bench, bodyweightKg: nil,
                                            experience: .novice, unit: .kg))
        XCTAssertNil(StartingWeight.suggest(for: bench, bodyweightKg: 0,
                                            experience: .novice, unit: .kg))
    }

    func testBodyweightMovementsGetNoSuggestedLoad() throws {
        for id in ["pull_up", "lying_leg_raise", "bw_calf_raise"] {
            let movement = try exercise(id)
            XCTAssertTrue(movement.isBodyweightLoaded, "\(id) should be bodyweight-loaded")
            XCTAssertNil(StartingWeight.suggest(for: movement, bodyweightKg: 80,
                                                experience: .novice, unit: .kg),
                         "\(id) has no external load to suggest")
        }
    }

    /// The dangerous user is the one who used to bench 100 kg and loads 100 kg
    /// on their first session back. Muscle memory returns faster than tendons.
    func testExperienceRaisesTheOpeningWeightButReturningLessThanExperienced() throws {
        let squat = try exercise("back_squat")
        let novice = try XCTUnwrap(StartingWeight.suggest(for: squat, bodyweightKg: 80,
                                                          experience: .novice, unit: .kg))
        let returning = try XCTUnwrap(StartingWeight.suggest(for: squat, bodyweightKg: 80,
                                                             experience: .returning, unit: .kg))
        let experienced = try XCTUnwrap(StartingWeight.suggest(for: squat, bodyweightKg: 80,
                                                               experience: .experienced, unit: .kg))
        XCTAssertLessThan(novice, returning)
        XCTAssertLessThan(returning, experienced)
        XCTAssertLessThan(experienced, 80, "even an experienced opener stays conservative")
    }

    func testHeavierPeopleGetHeavierOpeningWeights() throws {
        let squat = try exercise("back_squat")
        let light = try XCTUnwrap(StartingWeight.suggest(for: squat, bodyweightKg: 60,
                                                         experience: .novice, unit: .kg))
        let heavy = try XCTUnwrap(StartingWeight.suggest(for: squat, bodyweightKg: 100,
                                                         experience: .novice, unit: .kg))
        XCTAssertLessThan(light, heavy)
    }

    /// Rounding must go DOWN. Rounding up hands someone a heavier first set
    /// than intended, which is the direction that hurts.
    func testRoundingNeverExceedsTheComputedWeight() throws {
        let catalog = try Catalog.bundled()
        for movement in catalog.exercises {
            guard let ratio = movement.startRatio else { continue }
            for bodyweight in [52.0, 63.5, 77.0, 94.5, 120.0] {
                for experience in TrainingExperience.allCases {
                    guard let suggested = StartingWeight.suggest(
                        for: movement, bodyweightKg: bodyweight,
                        experience: experience, unit: .kg) else { continue }
                    let raw = bodyweight * ratio * experience.startMultiplier
                    let floor = StartingWeight.minimumLoad(for: movement, unit: .kg)
                    XCTAssertLessThanOrEqual(suggested, max(raw, floor) + 0.001,
                        "\(movement.id) at \(bodyweight)kg rounded UP to \(suggested)")
                }
            }
        }
    }

    /// Nothing absurd for anyone, at any size, in either unit. This is the
    /// blunt safety net behind the per-exercise ratios.
    func testNoSuggestionIsEverAbsurd() throws {
        let catalog = try Catalog.bundled()
        for movement in catalog.exercises {
            for bodyweight in [45.0, 70.0, 150.0] {
                for unit in [WeightUnit.kg, .lb] {
                    guard let suggested = StartingWeight.suggest(
                        for: movement, bodyweightKg: bodyweight,
                        experience: .experienced, unit: unit) else { continue }
                    XCTAssertGreaterThan(suggested, 0)
                    let asKg = unit == .kg ? suggested : suggested / 2.20462
                    XCTAssertLessThan(asKg, bodyweight * 1.6,
                        "\(movement.id): \(suggested)\(unit.rawValue) for a \(bodyweight)kg lifter")
                }
            }
        }
    }

    // MARK: - Through the engine

    func testFirstWorkoutComesPreFilledInsteadOfAsking() throws {
        let catalog = try Catalog.bundled()
        let gym: Set<String> = ["barbell", "rack", "bench", "dumbbells", "cable"]

        let blind = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                           minutes: 45, history: [])
        let asked = blind.exercises.filter { $0.weight == nil }.count
        XCTAssertGreaterThan(asked, 0, "without a bodyweight the app should still ask")

        let informed = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                              minutes: 45, history: [],
                                              bodyweightKg: 78, experience: .novice)
        let stillAsking = informed.exercises.filter { $0.weight == nil }
        XCTAssertTrue(stillAsking.isEmpty,
                      "still asking for: \(stillAsking.map(\.name).joined(separator: ", "))")

        for item in informed.exercises {
            XCTAssertFalse(item.reason.isEmpty, "\(item.name) has no reason shown")
        }
    }

    /// The product rule: every automatic number is shown with its reason, and
    /// the user is told they can change it.
    func testTheSuggestionSaysItIsAStartingPointAndChangeable() throws {
        let catalog = try Catalog.bundled()
        let plan = Engine.generateWorkout(catalog: catalog,
                                          gymEquipment: ["barbell", "rack", "bench"],
                                          minutes: 45, history: [],
                                          bodyweightKg: 78, experience: .novice)
        let suggested = try XCTUnwrap(plan.exercises.first { $0.weight != nil })
        let reason = suggested.reason.lowercased()
        XCTAssertTrue(reason.contains("starting point"), "reason was: \(suggested.reason)")
        XCTAssertTrue(reason.contains("change it"), "reason was: \(suggested.reason)")
    }

    /// A suggestion must never override real history. Once there is a logged
    /// session, bodyweight stops mattering entirely.
    func testHistoryAlwaysBeatsTheBodyweightSuggestion() throws {
        let catalog = try Catalog.bundled()
        let history = [Session(date: "2026-11-01", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press",
                           sets: [LoggedSet(weightKg: 72.5, reps: 10),
                                  LoggedSet(weightKg: 72.5, reps: 10)])
        ])]
        let plan = Engine.generateWorkout(catalog: catalog,
                                          gymEquipment: ["barbell", "rack", "bench"],
                                          minutes: 45, history: history,
                                          sessionType: "push",
                                          bodyweightKg: 78, experience: .novice)
        let bench = try XCTUnwrap(plan.exercises.first { $0.exerciseId == "bench_press" })
        XCTAssertGreaterThan(try XCTUnwrap(bench.weight), 70,
                             "history should drive the weight, not bodyweight")
        XCTAssertFalse(bench.reason.lowercased().contains("starting point"))
    }

    // MARK: - Settings compatibility

    /// Settings saved before these fields existed must still load. A failed
    /// decode would make an existing user look un-set-up and lose their gym.
    func testOldSettingsFilesStillDecode() throws {
        let old = Data("""
        {"equipment":["barbell","rack"],"minutes":45,"unit":"kg"}
        """.utf8)
        let settings = try JSONDecoder().decode(UserSettings.self, from: old)
        XCTAssertEqual(settings.minutes, 45)
        XCTAssertEqual(settings.equipment, ["barbell", "rack"])
        XCTAssertNil(settings.bodyweightKg)
        XCTAssertEqual(settings.experience, .novice, "a missing experience must default, not throw")
    }

    /// A typo must be REJECTED, not clamped. "7" or "800" silently becoming a
    /// real bodyweight would drive every opening weight from a bad number.
    func testBodyweightParsingRejectsNonsenseRatherThanClamping() {
        XCTAssertEqual(UserSettings.parseBodyweight("78", unit: .kg) ?? 0, 78, accuracy: 0.01)
        XCTAssertEqual(UserSettings.parseBodyweight(" 81.5 ", unit: .kg) ?? 0, 81.5, accuracy: 0.01)
        XCTAssertEqual(UserSettings.parseBodyweight("81,5", unit: .kg) ?? 0, 81.5, accuracy: 0.01)
        XCTAssertEqual(UserSettings.parseBodyweight("176", unit: .lb) ?? 0, 79.8, accuracy: 0.2)

        for nonsense in ["", "   ", "abc", "0", "-80", "7", "800", "1e9"] {
            XCTAssertNil(UserSettings.parseBodyweight(nonsense, unit: .kg),
                         "\"\(nonsense)\" should be rejected")
        }
    }

    func testNewSettingsRoundTrip() throws {
        let settings = UserSettings(equipment: ["dumbbells"], minutes: 30, unit: .lb,
                                    bodyweightKg: 81.5, experience: .returning)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: data), settings)
    }
}
