import XCTest
@testable import ZeroLogCore

/// The rules deciding when the app is allowed to log a set without asking.
///
/// This is the line between "it logs for you" and "it puts wrong numbers in
/// your history". A wrong number is worse than a missing one: it is harder to
/// spot, and it costs trust in every number that follows.
final class AutoLogTests: XCTestCase {

    private func planned(detectable: Bool = true, repProfile: String? = "squats",
                         name: String = "Barbell back squat") -> PlannedExercise {
        PlannedExercise(exerciseId: "back_squat", name: name, detectable: detectable,
                        repProfile: repProfile, sets: 3, weight: 60, targetReps: 8,
                        reason: "test", increment: 2.5, previousWeight: 60,
                        change: nil, kind: "compound", repRange: [5, 8])
    }

    private func detected(_ reps: Int, _ confidence: RepConfidence,
                          repProfile: String? = "squats") -> DetectedSet {
        DetectedSet(reps: reps, confidence: confidence, startedAt: 0, seconds: 25,
                    repProfile: repProfile)
    }

    // MARK: - When it logs on its own

    func testHighConfidenceLogsWithoutAsking() {
        let decision = AutoLog.decide(detected: detected(10, .high), exercise: planned(),
                                      suggestedWeight: 60, unit: .kg)
        guard case .logSilently(let reps, let weight, let note) = decision else {
            return XCTFail("a confident count on a known weight is the whole product, got \(decision)")
        }
        XCTAssertEqual(reps, 10)
        XCTAssertEqual(weight, 60)
        XCTAssertTrue(note.contains("10 reps"), "the note must say what was recorded: \(note)")
        XCTAssertTrue(note.contains("60 kg"), "and at what weight: \(note)")
        XCTAssertTrue(note.lowercased().contains("wrist"),
                      "and why it happened, per the show-the-reason rule: \(note)")
    }

    func testMediumConfidenceAsksForOneTapRatherThanLogging() {
        let decision = AutoLog.decide(detected: detected(10, .medium), exercise: planned(),
                                      suggestedWeight: 60, unit: .kg)
        guard case .askToConfirm = decision else {
            return XCTFail("medium confidence must not log silently, got \(decision)")
        }
    }

    /// Interrupting with a number we do not trust teaches the user to distrust
    /// the ones we do.
    func testLowConfidenceStaysQuietInsteadOfGuessing() {
        let decision = AutoLog.decide(detected: detected(10, .low), exercise: planned(),
                                      suggestedWeight: 60, unit: .kg)
        guard case .ignore = decision else {
            return XCTFail("low confidence must not suggest a number, got \(decision)")
        }
    }

    // MARK: - The guards that matter

    /// A leg press or a hanging knee raise keeps the wrist still. The catalogue
    /// knows; believe it rather than the signal.
    func testUndetectableExerciseIsNeverAutoLogged() {
        let decision = AutoLog.decide(detected: detected(10, .high),
                                      exercise: planned(detectable: false, repProfile: nil,
                                                        name: "Leg press"),
                                      suggestedWeight: 100, unit: .kg)
        guard case .ignore(let reason) = decision else {
            return XCTFail("a machine that does not move the wrist cannot be counted by it")
        }
        XCTAssertTrue(reason.contains("Leg press"), "say which exercise: \(reason)")
    }

    /// The single most important guard. Both rep estimators measure the same
    /// wrist, so a systematic misreading fools them identically and still
    /// reports high confidence -- on alternating curls both returned exactly 5
    /// against a true 10, every time. Only the per-exercise calibration catches
    /// that, so a count produced under the WRONG calibration must be discarded
    /// however confident it claims to be.
    func testCountFromTheWrongCalibrationIsRejectedEvenAtHighConfidence() {
        let decision = AutoLog.decide(detected: detected(5, .high, repProfile: "bicep_curls"),
                                      exercise: planned(repProfile: "squats"),
                                      suggestedWeight: 60, unit: .kg)
        guard case .ignore = decision else {
            return XCTFail("confidence from the wrong calibration is not confidence, got \(decision)")
        }
    }

    /// "Confirm, don't enter" still needs one entry: the first weight. The app
    /// must not invent it.
    func testFirstTimeAsksForTheWeightInsteadOfInventingOne() {
        let decision = AutoLog.decide(detected: detected(10, .high), exercise: planned(),
                                      suggestedWeight: nil, unit: .kg)
        guard case .askToConfirm(let reps, _, let note) = decision else {
            return XCTFail("with no history there is no weight to log, got \(decision)")
        }
        XCTAssertEqual(reps, 10, "the reps were still counted, only the weight is unknown")
        XCTAssertTrue(note.lowercased().contains("weight"), "say what is needed: \(note)")
    }

    func testNoExerciseInProgressIsIgnored() {
        let decision = AutoLog.decide(detected: detected(10, .high), exercise: nil,
                                      suggestedWeight: 60, unit: .kg)
        guard case .ignore = decision else { return XCTFail("nothing to log against") }
    }

    func testZeroRepsIsNeverLogged() {
        let decision = AutoLog.decide(detected: detected(0, .high), exercise: planned(),
                                      suggestedWeight: 60, unit: .kg)
        guard case .ignore = decision else { return XCTFail("an empty set is not a set") }
    }

    // MARK: - Wording

    /// Pounds users must not be shown kilograms.
    func testNoteUsesTheUsersUnit() {
        let decision = AutoLog.decide(detected: detected(10, .high), exercise: planned(),
                                      suggestedWeight: 135, unit: .lb)
        guard case .logSilently(_, _, let note) = decision else { return XCTFail() }
        XCTAssertTrue(note.contains("135 lb"), "expected pounds, got: \(note)")
    }

    /// No shaming, no streaks, no congratulation. It states what happened.
    func testNotesAreFlatStatementsNotCheerleading() {
        let banned = ["great", "awesome", "crushed", "beast", "keep it up", "don't break",
                      "streak", "failed", "missed", "only"]
        let confidences: [RepConfidence] = [.high, .medium]
        let notes: [String] = confidences.compactMap { confidence in
            switch AutoLog.decide(detected: detected(10, confidence), exercise: planned(),
                                  suggestedWeight: 60, unit: .kg) {
            case .logSilently(_, _, let n), .askToConfirm(_, _, let n): return n
            case .ignore: return nil
            }
        }
        XCTAssertEqual(notes.count, 2)
        for note in notes {
            for word in banned {
                XCTAssertFalse(note.lowercased().contains(word),
                               "\"\(word)\" has no place in a log line: \(note)")
            }
        }
    }
}
