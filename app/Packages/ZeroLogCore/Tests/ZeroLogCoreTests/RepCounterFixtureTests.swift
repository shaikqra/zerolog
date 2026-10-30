
import XCTest
@testable import ZeroLogCore

/// Cross-implementation check against the Python reference.
///
/// `scripts/rep_counter.py` is the implementation that was validated on MM-Fit
/// (21 workouts, 616 labelled sets, real smartwatch accelerometers). These
/// fixtures are REAL accelerometer traces from that dataset, paired with the
/// counts Python produced. If the Swift port drifts, these fail -- which is the
/// point: the validation numbers only describe the shipped app while the two
/// implementations agree.
///
/// Regenerate with scripts/make_fixtures.py after any pipeline change, and
/// re-run scripts/final_score.py to confirm accuracy did not move.
final class RepCounterFixtureTests: XCTestCase {

    struct Fixture: Decodable {
        let exercise: String
        let workout: String
        let wrist: String
        let fs: Double
        let trueReps: Int
        let expectedReps: Int
        let expectedConfidence: String
        let x: [Double]
        let y: [Double]
        let z: [Double]
    }

    func loadFixtures() throws -> [Fixture] {
        guard let url = Bundle.module.url(forResource: "rep_fixtures", withExtension: "json") else {
            XCTFail("rep_fixtures.json missing from the test bundle")
            return []
        }
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    func testSwiftMatchesThePythonReferenceOnRealGymData() throws {
        let fixtures = try loadFixtures()
        XCTAssertGreaterThan(fixtures.count, 15, "expected the full fixture set")

        var mismatches: [String] = []
        for f in fixtures {
            let got = RepCounter.count(sampleRateHz: f.fs, x: f.x, y: f.y, z: f.z,
                                       exercise: f.exercise == "__silence__" ? nil : f.exercise)
            if got.reps != f.expectedReps || got.confidence.rawValue != f.expectedConfidence {
                mismatches.append("""
                    \(f.exercise) \(f.workout)/\(f.wrist): \
                    python \(f.expectedReps)/\(f.expectedConfidence) \
                    vs swift \(got.reps)/\(got.confidence.rawValue) \
                    (peaks \(got.peakEstimate), autocorr \(got.autocorrEstimate))
                    """)
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "Swift diverged from the validated Python on \(mismatches.count) of "
                      + "\(fixtures.count) real sets:\n" + mismatches.joined(separator: "\n"))
    }

    /// The product claim is about high-confidence sets, so guard it directly.
    func testHighConfidenceSetsAreAccurateOnRealData() throws {
        let fixtures = try loadFixtures().filter { $0.exercise != "__silence__" }
        var high = 0, highWithinOne = 0
        for f in fixtures {
            let got = RepCounter.count(sampleRateHz: f.fs, x: f.x, y: f.y, z: f.z,
                                       exercise: f.exercise)
            if got.confidence == .high {
                high += 1
                if abs(got.reps - f.trueReps) <= 1 { highWithinOne += 1 }
            }
        }
        XCTAssertGreaterThan(high, 5, "expected several high-confidence sets in the fixtures")
        XCTAssertEqual(highWithinOne, high,
                       "a high-confidence set that is more than 1 rep out is the one failure "
                       + "mode the product must not have: it logs a wrong number silently")
    }

    /// A stationary watch must never invent a set. Regression guard: an all-zero
    /// signal previously returned "0 reps, medium", because zero peaks and zero
    /// autocorrelation were read as the estimators agreeing.
    func testStationaryWatchReportsLowConfidenceNotAgreement() {
        let flat = [Double](repeating: 0, count: 300)
        let got = RepCounter.count(sampleRateHz: 30, x: flat, y: flat, z: flat)
        XCTAssertEqual(got.reps, 0)
        XCTAssertEqual(got.confidence, .low)
    }

    /// Guards the bug that cost a 14%-accuracy false start: counting acceleration
    /// MAGNITUDE squares a signal that crosses zero, doubling its apparent
    /// frequency. The signed projection must not do that.
    func testProjectionDoesNotDoubleCountLikeMagnitudeWould() {
        let fs = 50.0, reps = 10.0, dur = 20.0
        let n = Int(fs * dur)
        var x = [Double](), zero = [Double]()
        for i in 0..<n {
            let t = Double(i) / fs
            x.append(sin(2 * .pi * (reps / dur) * t))
            zero.append(0)
        }
        let viaProjection = RepCounter.count(sampleRateHz: fs, x: x, y: zero, z: zero)
        XCTAssertLessThanOrEqual(abs(viaProjection.reps - 10), 1,
                                 "signed projection should recover 10 reps, got \(viaProjection.reps)")

        let magnitude = x.map { abs($0) }   // what squaring-then-rooting looks like
        let viaMagnitude = RepCounter.count(sampleRateHz: fs, x: magnitude, y: zero, z: zero)
        XCTAssertGreaterThan(viaMagnitude.reps, viaProjection.reps,
                             "magnitude must over-count, or this regression guard is not guarding")
    }
}
