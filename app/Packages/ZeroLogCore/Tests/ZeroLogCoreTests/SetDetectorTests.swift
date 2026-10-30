import XCTest
@testable import ZeroLogCore

/// Tests the zero-input promise: the watch has to work out where a set starts
/// and stops without being told. Runs on Linux because the logic lives in
/// ZeroLogCore and only the CoreMotion plumbing is device-only.
final class SetDetectorTests: XCTestCase {

    private let hz = 100.0

    /// Rhythmic movement, as a lift looks to a wrist: a swing on one axis with
    /// gravity sitting on another.
    private func lifting(reps: Int, seconds: Double, amplitudeG: Double = 0.35,
                         from startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(seconds * hz)
        let repsPerSecond = Double(reps) / seconds
        return (0..<n).map { i in
            let t = startTime + Double(i) / hz
            let phase = 2 * Double.pi * repsPerSecond * (Double(i) / hz)
            return MotionSample(t: t, x: amplitudeG * sin(phase), y: 0.02 * sin(phase * 0.3), z: 1.0)
        }
    }

    /// A wrist doing nothing: gravity plus a little sensor noise.
    private func resting(seconds: Double, from startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(seconds * hz)
        var seed = 42.0
        return (0..<n).map { i in
            seed = (seed * 16807).truncatingRemainder(dividingBy: 2147483647)
            let noise = (seed / 2147483647 - 0.5) * 0.012
            return MotionSample(t: startTime + Double(i) / hz, x: noise, y: noise * 0.5, z: 1.0 + noise)
        }
    }

    // MARK: - The core behaviour

    func testFindsASetWithoutBeingToldItStarted() {
        let detector = SetDetector(currentRepProfile: "squats")
        var found = detector.ingest(resting(seconds: 3))
        XCTAssertTrue(found.isEmpty, "standing still is not a set")

        found += detector.ingest(lifting(reps: 10, seconds: 25, from: 3))
        found += detector.ingest(resting(seconds: 8, from: 28))

        XCTAssertEqual(found.count, 1, "expected exactly one set")
        guard let set = found.first else { return }
        XCTAssertLessThanOrEqual(abs(set.reps - 10), 1,
                                 "expected about 10 reps, got \\(set.reps)")
        XCTAssertEqual(set.repProfile, "squats", "the calibration must be recorded with the set")
    }

    func testStillnessAloneNeverProducesASet() {
        let detector = SetDetector()
        XCTAssertTrue(detector.ingest(resting(seconds: 60)).isEmpty)
        XCTAssertNil(detector.flush(), "a watch on a bench must not invent a set")
    }

    func testTwoSetsSeparatedByRestAreCountedSeparately() {
        let detector = SetDetector(currentRepProfile: "squats")
        var found: [DetectedSet] = []
        found += detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        found += detector.ingest(resting(seconds: 10, from: 25))
        found += detector.ingest(lifting(reps: 8, seconds: 20, from: 35))
        found += detector.ingest(resting(seconds: 10, from: 55))

        XCTAssertEqual(found.count, 2, "rest between sets should split them")
        if found.count == 2 {
            XCTAssertLessThanOrEqual(abs(found[0].reps - 10), 1)
            XCTAssertLessThanOrEqual(abs(found[1].reps - 8), 1)
            XCTAssertGreaterThan(found[1].startedAt, found[0].startedAt)
        }
    }

    /// Racking a bar or adjusting a pin is a short burst, not a set.
    func testBriefMovementIsNotASet() {
        let detector = SetDetector()
        var found = detector.ingest(lifting(reps: 2, seconds: 2.0))
        found += detector.ingest(resting(seconds: 8, from: 2.0))
        XCTAssertTrue(found.isEmpty, "a 2-second burst is handling the weight, not lifting it")
    }

    /// A pause mid-set must not split one set into two.
    func testAShortPauseMidSetDoesNotSplitIt() {
        let detector = SetDetector(currentRepProfile: "squats")
        var found: [DetectedSet] = []
        found += detector.ingest(lifting(reps: 5, seconds: 12, from: 0))
        found += detector.ingest(resting(seconds: 2.0, from: 12))      // re-grip
        found += detector.ingest(lifting(reps: 5, seconds: 12, from: 14))
        found += detector.ingest(resting(seconds: 8, from: 26))
        XCTAssertEqual(found.count, 1,
                       "a 2-second pause is shorter than the end-of-set threshold")
    }

    /// Ending the workout while still at the rack must not lose the last set.
    func testFlushClosesASetStillInProgress() {
        let detector = SetDetector(currentRepProfile: "squats")
        XCTAssertTrue(detector.ingest(lifting(reps: 10, seconds: 25)).isEmpty,
                      "without trailing stillness the set is not closed yet")
        let set = detector.flush()
        XCTAssertNotNil(set, "the final set of a workout must still be counted")
        if let set { XCTAssertLessThanOrEqual(abs(set.reps - 10), 1) }
    }

    // MARK: - Honesty guarantees

    /// Only high-confidence sets may be logged without asking. This is the line
    /// between "it logs for you" and "it puts wrong numbers in your history".
    func testOnlyHighConfidenceSetsAreSilentlyLoggable() {
        let high = DetectedSet(reps: 10, confidence: .high, startedAt: 0, seconds: 25, repProfile: nil)
        let medium = DetectedSet(reps: 10, confidence: .medium, startedAt: 0, seconds: 25, repProfile: nil)
        let low = DetectedSet(reps: 10, confidence: .low, startedAt: 0, seconds: 25, repProfile: nil)
        XCTAssertTrue(high.isSilentlyLoggable)
        XCTAssertFalse(medium.isSilentlyLoggable)
        XCTAssertFalse(low.isSilentlyLoggable)
    }

    /// Thinning must be driven by timestamps, so a watch delivering 800 Hz and
    /// one delivering 100 Hz both end up counting the same reps.
    func testSameMovementAtDifferentSampleRatesGivesTheSameCount() {
        func run(at rate: Double) -> Int? {
            let detector = SetDetector(currentRepProfile: "squats")
            let n = Int(25 * rate)
            let samples = (0..<n).map { i -> MotionSample in
                let t = Double(i) / rate
                let phase = 2 * Double.pi * (10.0 / 25.0) * t
                return MotionSample(t: t, x: 0.35 * sin(phase), y: 0, z: 1.0)
            }
            detector.ingest(samples)
            return detector.flush()?.reps
        }
        let slow = run(at: 100)
        let fast = run(at: 800)
        XCTAssertNotNil(slow)
        XCTAssertEqual(slow, fast,
                       "sample rate is hardware-dependent; the rep count must not be")
    }

    /// Memory must be bounded: a watch left capturing cannot grow forever.
    func testBufferIsBoundedOverALongCapture() {
        let detector = SetDetector(currentRepProfile: "squats")
        for minute in 0..<12 {
            let from = Double(minute) * 60
            detector.ingest(lifting(reps: 20, seconds: 55, from: from))
            detector.ingest(resting(seconds: 5, from: from + 55))
        }
        XCTAssertLessThanOrEqual(detector.bufferedSampleCount, SetDetector.maxBufferedSamples,
                                 "the sample buffer must stay capped")
    }

    /// Samples arrive off the main actor while the UI sets the exercise on it.
    /// Those two really do race -- the watchOS build warned about exactly this,
    /// and Swift 6 will reject it outright. The lock inside SetDetector is what
    /// makes it safe; this proves the lock holds rather than trusting it.
    func testConcurrentIngestAndProfileChangesDoNotCorruptState() {
        let detector = SetDetector(currentRepProfile: "squats")
        let producers = 4
        let batchesEach = 40
        let done = expectation(description: "all producers finished")
        done.expectedFulfillmentCount = producers + 1

        for producer in 0..<producers {
            DispatchQueue.global().async {
                for batch in 0..<batchesEach {
                    let from = Double(producer * batchesEach + batch) * 1.5
                    detector.ingest(self.lifting(reps: 3, seconds: 1.5, from: from))
                    _ = detector.bufferedSampleCount
                    _ = detector.didDropSamples
                }
                done.fulfill()
            }
        }
        // Meanwhile the "UI" keeps changing which exercise is next.
        DispatchQueue.global().async {
            for i in 0..<200 {
                detector.currentRepProfile = i.isMultiple(of: 2) ? "squats" : "bicep_curls"
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 30)
        XCTAssertLessThanOrEqual(detector.bufferedSampleCount, SetDetector.maxBufferedSamples,
                                 "the buffer cap must hold under concurrent writers")
    }

    /// Timestamps stay session-relative on purpose: converting watch uptime to
    /// wall-clock reads system boot time, a required-reason API whose declared
    /// reason forbids that value leaving the device.
    func testSetTimestampsAreSessionRelativeNotWallClock() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        guard let set = detector.flush() else { return XCTFail("expected a set") }
        XCTAssertLessThan(set.startedAt, 60 * 60 * 24,
                          "startedAt should be an offset into the session, not an absolute date")
    }
}
