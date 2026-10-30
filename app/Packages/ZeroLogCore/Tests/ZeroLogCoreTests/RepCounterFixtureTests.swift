import XCTest
@testable import ZeroLogCore

/// Cross-implementation check: the Swift port must produce the same counts as
/// `scripts/rep_counter.py`, the implementation validated on MM-Fit.
///
/// The fixtures are SYNTHETIC, deliberately. MM-Fit's starter code is MIT but
/// the dataset itself grants no redistribution rights -- it only asks for a
/// citation -- so it is not ours to republish, least of all from a public repo
/// for a commercial product. It is also human-subjects data from 10
/// participants. Anyone can download it from mmfit.github.io and reproduce the
/// accuracy figures with `scripts/eval_mmfit.py`.
///
/// Synthetic costs nothing here, because this file's job is PARITY, not
/// accuracy. Accuracy is a separate claim, measured against the real dataset
/// with a subject-level holdout and recorded in the skill. Synthetic is in fact
/// better for parity: it targets the messy paths a clean sine wave skips --
/// slowing tempo, fading amplitude, sensor noise, a mid-set re-grip, movement
/// off the sensor axes, and rates from 50 to 200 Hz.
///
/// Regenerate with `scripts/make_fixtures.py`, then re-run
/// `scripts/final_score.py` to confirm real-data accuracy has not moved.
final class RepCounterFixtureTests: XCTestCase {

    struct Fixture: Decodable {
        let name: String
        let fs: Double
        let trueReps: Int
        /// What the Python reference produced for this exact input.
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

    private func count(_ f: Fixture) -> RepCount {
        RepCounter.count(sampleRateHz: f.fs, x: f.x, y: f.y, z: f.z,
                         exercise: f.name == "__silence__" ? nil : "squats")
    }

    /// The guarantee that matters: Swift and Python agree exactly. The MM-Fit
    /// accuracy numbers only describe the shipped app while they do.
    func testSwiftMatchesThePythonReferenceExactly() throws {
        let fixtures = try loadFixtures()
        XCTAssertGreaterThan(fixtures.count, 10, "expected the full fixture set")

        var mismatches: [String] = []
        for f in fixtures {
            let got = count(f)
            if got.reps != f.expectedReps || got.confidence.rawValue != f.expectedConfidence {
                mismatches.append("""
                    \(f.name): python \(f.expectedReps)/\(f.expectedConfidence) \
                    vs swift \(got.reps)/\(got.confidence.rawValue) \
                    (peaks \(got.peakEstimate), autocorr \(got.autocorrEstimate))
                    """)
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "Swift diverged from the validated Python on \(mismatches.count) of "
                      + "\(fixtures.count) cases:\n" + mismatches.joined(separator: "\n"))
    }

    /// Every case must land within a rep of the truth, including the awkward
    /// ones. A hard set slows down near failure and the amplitude fades -- that
    /// is the normal case, not an edge case.
    func testEveryCaseIsWithinOneRepOfTheTruth() throws {
        for f in try loadFixtures() where f.name != "__silence__" {
            let got = count(f)
            XCTAssertLessThanOrEqual(abs(got.reps - f.trueReps), 1,
                                     "\(f.name): counted \(got.reps), truth \(f.trueReps)")
        }
    }

    /// The one failure mode the product must not have: a confident wrong number
    /// logged silently into someone's history.
    func testNothingIsConfidentlyWrong() throws {
        for f in try loadFixtures() where f.name != "__silence__" {
            let got = count(f)
            if got.confidence == .high {
                XCTAssertLessThanOrEqual(abs(got.reps - f.trueReps), 1,
                                         "\(f.name) reported high confidence but was "
                                         + "\(abs(got.reps - f.trueReps)) reps out, which would be "
                                         + "logged with no tap")
            }
        }
    }

    /// Sample rate is hardware-dependent; the rep count must not be.
    func testRateDoesNotChangeTheCount() throws {
        let wanted = ["slow_rate_50hz", "clean_10_reps", "high_rate_200hz"]
        let rates = try loadFixtures().filter { wanted.contains($0.name) }
        XCTAssertEqual(rates.count, 3, "expected the 50, 100 and 200 Hz cases")
        let counts = Set(rates.map { count($0).reps })
        XCTAssertEqual(counts.count, 1,
                       "the same movement at 50/100/200 Hz gave different counts: \(counts)")
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
