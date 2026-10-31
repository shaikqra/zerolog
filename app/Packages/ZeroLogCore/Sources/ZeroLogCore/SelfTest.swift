import Foundation

/// Known motion traces with known answers, runnable anywhere.
///
/// Two jobs. On Linux they are ordinary tests. On a real watch they are a
/// one-tap self-test, which matters because the engine has never executed on
/// Apple hardware: arm64 floating point, a different Swift runtime and a
/// different Foundation all sit between the tested code and the device. If the
/// watch disagrees with Linux on the same input, that is a platform difference
/// and worth knowing in ten seconds rather than after a confusing gym session.
///
/// This is deliberately NOT a substitute for real lifting. It proves the
/// pipeline computes what it computed on Linux; it proves nothing about whether
/// a barbell bench press looks like what the tuner expects.
public enum SelfTest {

    public struct Trace: Sendable {
        public let name: String
        public let expectedSets: Int
        /// nil when the trace should produce no set at all.
        public let expectedReps: Int?
        public let tolerance: Int
        public let samples: [MotionSample]
    }

    public struct Result: Sendable, Equatable {
        public let name: String
        public let passed: Bool
        /// Short enough for a watch screen.
        public let detail: String
    }

    /// A clean rhythmic set.
    static func set(reps: Int, secondsPerRep: Double, from: TimeInterval,
                    hz: Double = 50, amplitude: Double = 0.35) -> [MotionSample] {
        let duration = Double(reps) * secondsPerRep
        let n = Int(duration * hz)
        return (0..<n).map { i in
            let t = Double(i) / hz
            let phase = 2 * Double.pi * (Double(reps) / duration) * t
            // Gravity on z, movement mostly on x, a little cross-axis coupling:
            // a wrist never moves on exactly one axis.
            return MotionSample(t: from + t,
                                x: amplitude * sin(phase),
                                y: 0.08 * sin(phase * 1.3),
                                z: 1.0 + 0.05 * cos(phase))
        }
    }

    static func rest(seconds: Double, from: TimeInterval, hz: Double = 50) -> [MotionSample] {
        let n = Int(seconds * hz)
        var seed = 7.0
        return (0..<n).map { i in
            seed = (seed * 16807).truncatingRemainder(dividingBy: 2147483647)
            let noise = (seed / 2147483647 - 0.5) * 0.01
            return MotionSample(t: from + Double(i) / hz, x: noise, y: noise * 0.4, z: 1.0 + noise)
        }
    }

    /// The checks, chosen to cover the failures that have actually happened in
    /// this codebase rather than a tidy spread of cases.
    public static func traces() -> [Trace] {
        [
            Trace(name: "Normal set", expectedSets: 1, expectedReps: 10, tolerance: 1,
                  samples: set(reps: 10, secondsPerRep: 2.0, from: 0)
                           + rest(seconds: 8, from: 20)),

            // The bug that a one-second energy window caused: slow reps read as
            // rest and split one set in two.
            Trace(name: "Slow grind", expectedSets: 1, expectedReps: 5, tolerance: 1,
                  samples: set(reps: 5, secondsPerRep: 3.0, from: 100)
                           + rest(seconds: 8, from: 115)),

            // Must not be a set: racking a bar, adjusting a pin.
            Trace(name: "Short burst ignored", expectedSets: 0, expectedReps: nil, tolerance: 0,
                  samples: set(reps: 2, secondsPerRep: 1.0, from: 200)
                           + rest(seconds: 8, from: 202)),

            // Must not invent anything from a still wrist.
            Trace(name: "Stillness ignored", expectedSets: 0, expectedReps: nil, tolerance: 0,
                  samples: rest(seconds: 30, from: 300)),

            // Two sets split by a real rest, not merged into one.
            Trace(name: "Two sets split", expectedSets: 2, expectedReps: nil, tolerance: 0,
                  samples: set(reps: 8, secondsPerRep: 2.0, from: 400)
                           + rest(seconds: 10, from: 416)
                           + set(reps: 8, secondsPerRep: 2.0, from: 426)
                           + rest(seconds: 10, from: 442)),

            // The suspension case: a gap in delivery must not become one giant
            // set stitched across ten minutes of nothing.
            Trace(name: "Delivery gap", expectedSets: 2, expectedReps: nil, tolerance: 0,
                  samples: set(reps: 8, secondsPerRep: 2.0, from: 500)
                           + set(reps: 8, secondsPerRep: 2.0, from: 1116)
                           + rest(seconds: 8, from: 1132)),
        ]
    }

    /// Runs every trace through a real `SetDetector`, exactly as live motion
    /// would be. Returns one line per trace, fit to show on a watch.
    public static func run(profile: String? = nil) -> [Result] {
        traces().map { trace in
            let detector = SetDetector(currentRepProfile: profile)
            var found: [DetectedSet] = []
            // Fed in small batches, like real sensor delivery.
            for chunk in trace.samples.chunked(into: 64) {
                found += detector.ingest(chunk)
            }
            if let last = detector.flush() { found.append(last) }

            guard found.count == trace.expectedSets else {
                return Result(name: trace.name, passed: false,
                              detail: "\(found.count) sets, expected \(trace.expectedSets)")
            }
            if let expected = trace.expectedReps {
                let reps = found.first?.reps ?? 0
                let ok = abs(reps - expected) <= trace.tolerance
                return Result(name: trace.name, passed: ok,
                              detail: "\(reps) reps, expected \(expected)")
            }
            return Result(name: trace.name, passed: true,
                          detail: "\(found.count) sets")
        }
    }

    /// One line summarising a run, for the top of the screen.
    public static func summary(_ results: [Result]) -> String {
        let passed = results.filter(\.passed).count
        return "\(passed)/\(results.count) passed"
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
