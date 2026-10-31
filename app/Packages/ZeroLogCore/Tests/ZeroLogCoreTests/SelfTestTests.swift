import XCTest
@testable import ZeroLogCore

/// The self-test must pass HERE, so that a failure ON THE WATCH means a platform
/// difference rather than a bad expectation. That is the whole value of it: the
/// engine has never run on Apple hardware, and arm64 floating point, a different
/// Swift runtime and a different Foundation all sit in between.
final class SelfTestTests: XCTestCase {

    func testEveryTracePassesOnThisPlatform() {
        let results = SelfTest.run()
        let failures = results.filter { !$0.passed }
        XCTAssertTrue(failures.isEmpty,
                      "self-test expectations are wrong on Linux: "
                      + failures.map { "\($0.name) -> \($0.detail)" }.joined(separator: " | "))
        XCTAssertEqual(SelfTest.summary(results), "\(results.count)/\(results.count) passed")
    }

    /// Batch size must not change the answer. Real delivery arrives in whatever
    /// chunks the hardware chooses, and CMBatchedSensorManager chunks differently
    /// from CMMotionManager.
    func testResultsAreIndependentOfBatchSize() {
        for size in [1, 7, 64, 512, 10_000] {
            for trace in SelfTest.traces() {
                let detector = SetDetector()
                var found: [DetectedSet] = []
                for chunk in trace.samples.chunked(into: size) {
                    found += detector.ingest(chunk)
                }
                if let last = detector.flush() { found.append(last) }
                XCTAssertEqual(found.count, trace.expectedSets,
                               "\(trace.name) at batch size \(size) found \(found.count) sets")
            }
        }
    }

    func testChunkingIsLossless() {
        let samples = SelfTest.set(reps: 10, secondsPerRep: 2, from: 0)
        for size in [1, 3, 64, 1000, 100_000] {
            let chunks = samples.chunked(into: size)
            XCTAssertEqual(chunks.flatMap { $0 }.count, samples.count, "lost samples at size \(size)")
            XCTAssertEqual(chunks.flatMap { $0 }.map(\.t), samples.map(\.t), "reordered at size \(size)")
        }
    }
}
