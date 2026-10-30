import XCTest
@testable import ZeroLogCore

/// Hostile input. Nothing here is a realistic workout; everything here is
/// something a sensor, a suspended app or a scheduler can actually produce.
///
/// The counting accuracy is measured elsewhere. This file asks a different and
/// blunter question: can the engine be made to crash, hang, or report something
/// absurd? Those are the failures a user would actually notice, and none of the
/// accuracy work touches them.
final class AdversarialInputTests: XCTestCase {

    // MARK: - RepCounter

    /// Adapts a sample list to the counter's axis-array API.
    private func count(_ samples: [MotionSample], fs: Double = 50,
                       exercise: String? = nil) -> RepCount {
        RepCounter.count(sampleRateHz: fs,
                         x: samples.map(\.x), y: samples.map(\.y), z: samples.map(\.z),
                         exercise: exercise)
    }

    func testDegenerateWindowsReturnNothingRatherThanCrashing() {
        let cases: [(String, [MotionSample])] = [
            ("empty", []),
            ("one sample", [MotionSample(t: 0, x: 0, y: 0, z: 1)]),
            ("two samples", [MotionSample(t: 0, x: 0, y: 0, z: 1),
                             MotionSample(t: 0.02, x: 0.1, y: 0, z: 1)]),
            ("all identical", (0..<200).map {
                MotionSample(t: Double($0) / 50, x: 0.5, y: 0.5, z: 0.5) }),
            ("all zero", (0..<200).map {
                MotionSample(t: Double($0) / 50, x: 0, y: 0, z: 0) }),
        ]
        for (name, samples) in cases {
            let result = count(samples)
            XCTAssertEqual(result.reps, 0, "\(name) should count nothing")
            XCTAssertEqual(result.confidence, .low, "\(name) should not claim confidence")
        }
    }

    /// A tremor, a phone vibration, a bumpy car ride. High-frequency motion must
    /// not be read as hundreds of reps: the band-pass filter exists precisely to
    /// reject it, and this proves it does.
    func testVibrationIsNotCountedAsReps() {
        let samples = (0..<(50 * 20)).map { i -> MotionSample in
            let t = Double(i) / 50
            return MotionSample(t: t, x: 0.4 * sin(2 * .pi * 20 * t), y: 0, z: 1)
        }
        let result = count(samples)
        XCTAssertLessThan(result.reps, 5,
                          "20 Hz vibration read as \(result.reps) reps")
    }

    /// Sub-rep-rate sway: walking to the water fountain, a bus, a bad treadmill.
    func testVerySlowDriftIsNotCountedAsReps() {
        let samples = (0..<(50 * 30)).map { i -> MotionSample in
            let t = Double(i) / 50
            return MotionSample(t: t, x: 0.6 * sin(2 * .pi * 0.05 * t), y: 0, z: 1)
        }
        let result = count(samples)
        XCTAssertLessThan(result.reps, 4, "0.05 Hz sway read as \(result.reps) reps")
    }

    /// Non-finite values should never reach us, but a single NaN propagating
    /// through a filter turns every downstream number into NaN, and `Int(nan)`
    /// traps in Swift. A crash in the gym is worse than a wrong count.
    func testNonFiniteSamplesDoNotCrashOrProduceNonsense() {
        for bad in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            var samples = (0..<200).map { i -> MotionSample in
                let t = Double(i) / 50
                return MotionSample(t: t, x: 0.3 * sin(2 * .pi * 0.5 * t), y: 0, z: 1)
            }
            samples[100] = MotionSample(t: 2.0, x: bad, y: bad, z: bad)
            let result = count(samples)
            XCTAssertTrue((0...500).contains(result.reps),
                          "a \(bad) sample produced \(result.reps) reps")
        }
    }

    /// Absurd magnitudes: a dropped watch, a sensor fault.
    func testExtremeMagnitudesStayBounded() {
        let samples = (0..<(50 * 20)).map { i -> MotionSample in
            let t = Double(i) / 50
            return MotionSample(t: t, x: 5000 * sin(2 * .pi * 0.5 * t), y: 0, z: 1)
        }
        let result = count(samples)
        XCTAssertTrue((0...100).contains(result.reps),
                      "huge amplitude produced \(result.reps) reps")
    }

    /// Batched sensor delivery can hand us samples out of order, and duplicate
    /// timestamps appear when a batch boundary repeats a reading.
    func testDisorderedAndDuplicateTimestampsAreSurvivable() {
        var samples = (0..<(50 * 15)).map { i -> MotionSample in
            let t = Double(i) / 50
            return MotionSample(t: t, x: 0.35 * sin(2 * .pi * 0.5 * t), y: 0, z: 1)
        }
        samples.swapAt(100, 160)
        samples.swapAt(300, 301)
        samples.append(samples[200])
        let result = count(samples)
        XCTAssertTrue((0...60).contains(result.reps),
                      "disordered input produced \(result.reps) reps")
    }

    // MARK: - SetDetector

    private func lifting(reps: Int, seconds: Double, from: TimeInterval,
                         hz: Double = 50) -> [MotionSample] {
        (0..<Int(seconds * hz)).map { i in
            let t = Double(i) / hz
            return MotionSample(t: from + t,
                                x: 0.35 * sin(2 * .pi * (Double(reps) / seconds) * t),
                                y: 0, z: 1)
        }
    }

    private func resting(seconds: Double, from: TimeInterval,
                         hz: Double = 50) -> [MotionSample] {
        (0..<Int(seconds * hz)).map {
            MotionSample(t: from + Double($0) / hz, x: 0.001, y: 0, z: 1)
        }
    }

    func testEmptyAndSingleSampleBatchesAreHarmless() {
        let detector = SetDetector(currentRepProfile: "squats")
        XCTAssertTrue(detector.ingest([]).isEmpty)
        XCTAssertTrue(detector.ingest([MotionSample(t: 0, x: 0, y: 0, z: 1)]).isEmpty)
        XCTAssertTrue(detector.ingest([]).isEmpty)
    }

    /// THE SUSPENSION CASE. watchOS can stop delivering motion mid-set -- the
    /// workout session makes that unlikely, not impossible. When samples resume
    /// ten minutes later, the set in progress must not become a ten-minute set
    /// with an absurd rep count stitched across the gap.
    func testALongDeliveryGapDoesNotProduceAMonstrousSet() {
        let detector = SetDetector(currentRepProfile: "squats")
        var found = detector.ingest(lifting(reps: 5, seconds: 12, from: 0))
        // Ten minutes of nothing at all: no samples, not even quiet ones.
        found += detector.ingest(lifting(reps: 5, seconds: 12, from: 612))
        found += detector.ingest(resting(seconds: 8, from: 624))

        for set in found {
            XCTAssertLessThan(set.seconds, 180,
                              "a set of \(Int(set.seconds))s spans the suspension gap")
            XCTAssertLessThan(set.reps, 60, "a set of \(set.reps) reps is not real")
        }
    }

    /// Time going backwards: a clock correction, or batches racing.
    func testTimestampsGoingBackwardsDoNotStallDetectionForever() {
        let detector = SetDetector(currentRepProfile: "squats")
        _ = detector.ingest(lifting(reps: 5, seconds: 12, from: 100))
        // A batch from the past arrives.
        _ = detector.ingest(lifting(reps: 2, seconds: 3, from: 40))
        // Then normal time resumes and a real set happens.
        var found = detector.ingest(lifting(reps: 8, seconds: 20, from: 112))
        found += detector.ingest(resting(seconds: 8, from: 132))
        XCTAssertFalse(found.isEmpty,
                       "detection stalled permanently after a backwards timestamp")
    }

    func testNonFiniteSamplesDoNotCrashTheDetector() {
        let detector = SetDetector(currentRepProfile: "squats")
        var batch = lifting(reps: 5, seconds: 12, from: 0)
        batch[50] = MotionSample(t: batch[50].t, x: .nan, y: .infinity, z: .nan)
        _ = detector.ingest(batch)
        let found = detector.ingest(resting(seconds: 8, from: 12))
        for set in found {
            XCTAssertTrue((0...100).contains(set.reps),
                          "non-finite input produced \(set.reps) reps")
        }
    }

    /// A 90-minute session at 800 Hz is far beyond anything real, which is the
    /// point: memory must stay bounded and the thing must not slow down as it
    /// goes. A detector that degrades over an hour fails exactly when the user
    /// is deepest into their workout.
    func testALongHighRateSessionStaysBoundedAndFast() {
        let detector = SetDetector(currentRepProfile: "squats")
        var t = 0.0
        var sets = 0
        let started = Date()
        // 30 sets with rests: roughly an hour of wall-clock training.
        for _ in 0..<30 {
            sets += detector.ingest(lifting(reps: 10, seconds: 30, from: t, hz: 800)).count
            t += 30
            sets += detector.ingest(resting(seconds: 60, from: t, hz: 800)).count
            t += 60
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(sets, 20, "only \(sets) of 30 sets were found")
        XCTAssertLessThan(detector.bufferedSampleCount, 20_000,
                          "buffer grew to \(detector.bufferedSampleCount) samples")
        XCTAssertLessThan(elapsed, 60,
                          "an hour of motion took \(Int(elapsed))s to process")
        XCTAssertLessThanOrEqual(detector.recordedSets.count, SetDetector.maxRecordedSets)
    }

    /// Changing exercise while samples are arriving, repeatedly, from several
    /// producers. Already covered once, but combined here with recording on,
    /// which adds a second mutable collection behind the same lock.
    func testConcurrentIngestAndProfileChangesWithRecordingOn() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        let group = DispatchGroup()
        for producer in 0..<4 {
            DispatchQueue.global().async(group: group) {
                var t = Double(producer) * 1000
                for _ in 0..<40 {
                    _ = detector.ingest(self.lifting(reps: 10, seconds: 25, from: t))
                    _ = detector.ingest(self.resting(seconds: 8, from: t + 25))
                    t += 33
                }
            }
        }
        DispatchQueue.global().async(group: group) {
            for i in 0..<200 {
                detector.currentRepProfile = i % 2 == 0 ? "squats" : "bicep_curls"
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success,
                       "concurrent ingest and profile changes deadlocked")
    }
}
