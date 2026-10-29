import XCTest
@testable import ZeroLogCore

/// Plate maths, strength numbers and the onboarding profile.
/// These tests are the specification -- change them first.
final class PlateMathTests: XCTestCase {

    func testOneHundredKilosIsTwentyBarPlusTwoFortiesOfPlates() {
        let l = PlateMath.load(target: 100, unit: .kg)!
        XCTAssertEqual(l.perSide, [25, 15])         // 40 per side + 20 bar = 100
        XCTAssertEqual(l.achievedWeight, 100)
        XCTAssertFalse(l.isApproximate)
    }

    func testClassicTwoPlatesEachSideInPounds() {
        let l = PlateMath.load(target: 225, unit: .lb)!
        XCTAssertEqual(l.perSide, [45, 45])
        XCTAssertEqual(l.achievedWeight, 225)
        XCTAssertEqual(l.describe(unit: .lb), "2 x 45 per side")
    }

    func testEmptyBarLoadsNothing() {
        let l = PlateMath.load(target: 20, unit: .kg)!
        XCTAssertTrue(l.perSide.isEmpty)
        XCTAssertEqual(l.describe(unit: .kg), "Empty bar")
    }

    func testBelowBarWeightIsRefusedRatherThanFaked() {
        XCTAssertNil(PlateMath.load(target: 15, unit: .kg))
    }

    func testUnmakeableWeightIsFlaggedApproximateNotRoundedSilently() {
        // 21 kg needs 0.5 per side; the lightest plate is 1.25.
        let l = PlateMath.load(target: 21, unit: .kg)!
        XCTAssertTrue(l.perSide.isEmpty)
        XCTAssertEqual(l.achievedWeight, 20)
        XCTAssertTrue(l.isApproximate)
    }

    func testDescriptionGroupsRepeatedPlates() {
        let l = PlateMath.load(target: 80, unit: .kg)!   // 30 per side = 25 + 5
        XCTAssertEqual(l.describe(unit: .kg), "1 x 25 + 1 x 5 per side")
    }

    func testFractionalPlatesKeepTheirDecimal() {
        let l = PlateMath.load(target: 45, unit: .kg)!   // 12.5 per side = 10 + 2.5
        XCTAssertEqual(l.perSide, [10, 2.5])
        XCTAssertEqual(l.describe(unit: .kg), "1 x 10 + 1 x 2.5 per side")
    }
}

final class StrengthTests: XCTestCase {

    func testSingleRepIsItsOwnOneRepMax() {
        XCTAssertEqual(Strength.estimatedOneRepMax(weight: 100, reps: 1), 100)
    }

    func testEpleyOnAFiveRepSet() {
        // 100 * (1 + 5/30) = 116.67
        XCTAssertEqual(Strength.estimatedOneRepMax(weight: 100, reps: 5)!, 116.67, accuracy: 0.01)
    }

    func testVeryHighRepSetsReturnNilRatherThanAConfidentLie() {
        XCTAssertNil(Strength.estimatedOneRepMax(weight: 60, reps: 20))
        XCTAssertNil(Strength.estimatedOneRepMax(weight: 60, reps: 0))
    }

    func testBestOneRepMaxScansEverySet() {
        let history = [
            Session(date: "2026-10-01", sessionType: "push", exercises: [
                LoggedExercise(exerciseId: "bench_press", sets: [
                    LoggedSet(weightKg: 80, reps: 5),     // 93.33
                    LoggedSet(weightKg: 90, reps: 3),     // 99.0  <- best
                ])
            ])
        ]
        XCTAssertEqual(Strength.bestEstimatedOneRepMaxKg(history: history, exerciseId: "bench_press")!,
                       99.0, accuracy: 0.01)
        XCTAssertNil(Strength.bestEstimatedOneRepMaxKg(history: history, exerciseId: "squat"))
    }

    func testVolumeIsWeightTimesReps() {
        let session = Session(date: "2026-10-01", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [
                LoggedSet(weightKg: 60, reps: 10),        // 600
                LoggedSet(weightKg: 60, reps: 8),         // 480
            ])
        ])
        XCTAssertEqual(Strength.volumeKg(session), 1080)
    }

    func testPersonalBestNeedsSomethingToBeat() {
        let empty: [Session] = []
        XCTAssertFalse(Strength.isPersonalBest(history: empty, exerciseId: "bench_press",
                                               weightKg: 100, reps: 3))
        let history = [
            Session(date: "2026-10-01", sessionType: "push", exercises: [
                LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 80, reps: 5)])
            ])
        ]
        XCTAssertTrue(Strength.isPersonalBest(history: history, exerciseId: "bench_press",
                                              weightKg: 90, reps: 3))
        XCTAssertFalse(Strength.isPersonalBest(history: history, exerciseId: "bench_press",
                                               weightKg: 70, reps: 5))
    }
}

final class ProfileTests: XCTestCase {

    private func profile(_ goal: Goal) -> UserProfile {
        UserProfile(birthYear: 2008, heightCm: 178, sex: .male, goal: goal)
    }

    func testAgeIsDerivedNotStored() {
        XCTAssertEqual(profile(.maintain).age(inYear: 2026), 18)
    }

    func testRestingEnergyMatchesMifflinStJeor() {
        // 10*80 + 6.25*178 - 5*18 + 5 = 1827.5
        let value = Nutrition.restingEnergy(profile: profile(.maintain), weightKg: 80, year: 2026)
        XCTAssertEqual(value, 1827.5, accuracy: 0.01)
    }

    func testCaloriesAreAlwaysARangeNeverASingleNumber() {
        let t = Nutrition.seedTargets(profile: profile(.maintain), weightKg: 80, year: 2026)
        XCTAssertLessThan(t.caloriesLow, t.caloriesHigh)
    }

    func testGoalMovesCaloriesInTheRightDirection() {
        let lose = Nutrition.seedTargets(profile: profile(.loseFat), weightKg: 80, year: 2026)
        let hold = Nutrition.seedTargets(profile: profile(.maintain), weightKg: 80, year: 2026)
        let gain = Nutrition.seedTargets(profile: profile(.buildMuscle), weightKg: 80, year: 2026)
        XCTAssertLessThan(lose.caloriesHigh, hold.caloriesHigh)
        XCTAssertGreaterThan(gain.caloriesHigh, hold.caloriesHigh)
    }

    func testProteinScalesWithBodyweightAndFatHasAFloor() {
        let light = Nutrition.seedTargets(profile: profile(.loseFat), weightKg: 45, year: 2026)
        XCTAssertEqual(light.proteinG, 90)
        XCTAssertEqual(light.fatG, 40, "fat floor protects hormone health on a cut")
    }

    func testBodyweightIsASeriesNotASingleNumber() {
        var p = profile(.maintain)
        XCTAssertNil(p.latestBodyweightKg)
        p.bodyweightLog = [BodyweightEntry(date: "2026-10-29", kg: 80.4),
                           BodyweightEntry(date: "2026-10-22", kg: 81.0)]
        XCTAssertEqual(p.latestBodyweightKg, 80.4)
    }

    /// Guideline 5.1.3(ii): no personal health information in iCloud.
    /// If someone removes this conformance, a future sync layer loses the only
    /// signal telling it not to upload bodyweight, height, DOB and sex.
    func testHealthBearingTypesAreMarkedDeviceLocalOnly() {
        XCTAssertTrue((profile(.maintain) as Any) is DeviceLocalOnly)
        XCTAssertTrue((BodyweightEntry(date: "2026-10-29", kg: 80) as Any) is DeviceLocalOnly)
        XCTAssertTrue((MacroTargets(caloriesLow: 2000, caloriesHigh: 2200, proteinG: 160,
                                    fatG: 65, carbsG: 200) as Any) is DeviceLocalOnly)
    }

    func testProfileSurvivesASaveAndLoad() throws {
        let p = profile(.buildMuscle)
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(UserProfile.self, from: data), p)
    }
}
