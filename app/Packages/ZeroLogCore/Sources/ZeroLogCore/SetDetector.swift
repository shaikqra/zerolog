import Foundation

/// One accelerometer reading from the watch.
///
/// `x/y/z` are in **g**, and gravity may or may not be included -- the rep
/// counter's 0.2 Hz high-pass removes any constant component either way, so the
/// capture layer does not have to strip it. What matters is that the scale is g
/// and stays consistent, because `SetDetector` compares movement energy against
/// an absolute threshold expressed in g.
public struct MotionSample: Equatable, Sendable {
    /// Seconds, monotonic within one capture session. Does not have to be
    /// wall-clock: see the privacy note on `SetDetector`.
    public let t: TimeInterval
    public let x: Double
    public let y: Double
    public let z: Double

    public init(t: TimeInterval, x: Double, y: Double, z: Double) {
        self.t = t
        self.x = x
        self.y = y
        self.z = z
    }

    var axes: [Double] { [x, y, z] }
}

/// A set the watch spotted on its own, with no tap to start or stop it.
public struct DetectedSet: Equatable, Sendable {
    public let reps: Int
    public let confidence: RepConfidence
    /// Seconds into the capture session where the movement began.
    public let startedAt: TimeInterval
    public let seconds: Double
    /// Which calibration was used, or nil for the generic profile.
    public let repProfile: String?

    /// Whether this can be logged without asking. Everything else gets a tap.
    public var isSilentlyLoggable: Bool { confidence == .high }
}

/// Watches a continuous stream of wrist motion and decides where sets begin and
/// end, then counts the reps in each.
///
/// This is the piece that makes the product "zero input": the user never tells
/// the app a set started. It lives in ZeroLogCore, not the watch target, so the
/// decision logic is testable on Linux -- only the CoreMotion plumbing is
/// device-only.
///
/// PRIVACY: timestamps here are relative to the start of capture, deliberately.
/// Converting `CMLogItem.timestamp` (seconds since boot) to wall-clock reads
/// system boot time, which is a required-reason API: declaring `35F9.1` means
/// that value may never leave the device. Keeping session-relative offsets
/// avoids the question entirely. Do not "improve" this by storing absolute dates
/// in the sample stream.
///
/// BATTERY: this assumes the caller only captures during an active workout.
/// High-rate accelerometer capture for a whole session is expensive and has NOT
/// been measured on hardware yet.
public final class SetDetector {

    // MARK: Tuning

    /// Samples are thinned to this rate before counting. Reps live below 2 Hz,
    /// so 50 Hz is far above what the algorithm needs, and the watch may deliver
    /// several hundred Hz. Thinning cuts memory and CPU with no accuracy cost.
    public static let targetHz: Double = 50

    /// Movement energy above which a one-second window counts as "working",
    /// measured as the mean per-axis standard deviation in g. A resting wrist
    /// sits around 0.01 g; lifting is an order of magnitude above that.
    ///
    /// Per-AXIS deliberately, not the magnitude: sqrt(x^2+y^2+z^2) is dominated
    /// by the 1 g of gravity, and the quadratic flattens real movement into a
    /// tiny ripple (a 0.3 g swing shows up as roughly 0.04 g of variation, below
    /// this threshold). That is the same mistake that made the first rep counter
    /// read 14% accuracy. Never measure movement through the magnitude.
    public static let activeThresholdG: Double = 0.05

    /// Stillness this long ends a set. Long enough to survive a pause or a
    /// re-grip mid-set, short enough that the summary appears promptly.
    public static let quietSecondsToEndSet: Double = 4.0

    /// Shorter bursts than this are racking the weight, not a set.
    public static let minSetSeconds: Double = 4.0

    /// Hard cap on buffered samples, so a watch left recording cannot grow
    /// without bound. 50 Hz x 300 s is a five-minute set, far beyond real.
    static let maxBufferedSamples = Int(targetHz * 300)

    // MARK: State

    /// Which exercise the engine says is next. Set this BEFORE the set happens:
    /// per-exercise calibration is the only defence against both estimators
    /// agreeing on a wrong number.
    public var currentRepProfile: String?

    private var buffer: [MotionSample] = []
    private var lastKeptTime: TimeInterval?
    private var windowStart: TimeInterval?
    private var windowSamples: [MotionSample] = []
    private var activeSince: TimeInterval?
    private var quietSince: TimeInterval?
    private var droppedForOverflow = false

    public init(currentRepProfile: String? = nil) {
        self.currentRepProfile = currentRepProfile
    }

    // MARK: Input

    /// Feeds a batch of samples in and returns any sets that completed.
    ///
    /// Returns an array because one batch can, in principle, close more than one
    /// set -- a caller that resumes after a gap should not silently lose data.
    @discardableResult
    public func ingest(_ samples: [MotionSample]) -> [DetectedSet] {
        var finished: [DetectedSet] = []
        for sample in samples {
            // 1. Thin to targetHz, using timestamps rather than assuming a rate.
            if let last = lastKeptTime, sample.t - last < 1.0 / Self.targetHz { continue }
            lastKeptTime = sample.t

            buffer.append(sample)
            if buffer.count > Self.maxBufferedSamples {
                buffer.removeFirst(buffer.count - Self.maxBufferedSamples)
                droppedForOverflow = true
            }

            // 2. Accumulate one-second windows and classify each as work or rest.
            if windowStart == nil { windowStart = sample.t }
            windowSamples.append(sample)
            guard let start = windowStart, sample.t - start >= 1.0 else { continue }

            let energy = (0..<3)
                .map { axis in RepCounter.standardDeviation(windowSamples.map { $0.axes[axis] }) }
                .reduce(0, +) / 3.0
            let windowEnd = sample.t
            windowSamples.removeAll(keepingCapacity: true)
            windowStart = nil

            if energy > Self.activeThresholdG {
                if activeSince == nil { activeSince = start }
                quietSince = nil
            } else if activeSince != nil {
                if quietSince == nil { quietSince = start }
                if let quiet = quietSince, windowEnd - quiet >= Self.quietSecondsToEndSet {
                    if let set = closeSet(endingAt: quiet) { finished.append(set) }
                }
            } else {
                // Idle before any work: keep the buffer short.
                trimBuffer(before: windowEnd - Self.quietSecondsToEndSet)
            }
        }
        return finished
    }

    /// Closes any set still in progress, for when the user ends the workout
    /// while standing at the rack. Without this the final set would be lost.
    public func flush() -> DetectedSet? {
        guard activeSince != nil, let last = buffer.last?.t else { return nil }
        return closeSet(endingAt: last)
    }

    public func reset() {
        buffer.removeAll()
        windowSamples.removeAll()
        lastKeptTime = nil
        windowStart = nil
        activeSince = nil
        quietSince = nil
        droppedForOverflow = false
    }

    /// True when samples were discarded to respect the memory cap, which means
    /// the next count covers less than the whole set. Surface it rather than
    /// reporting a confident number from partial data.
    public var didDropSamples: Bool { droppedForOverflow }

    /// Exposed so a test can prove the buffer stays capped.
    public var bufferedSampleCount: Int { buffer.count }

    // MARK: Counting

    private func closeSet(endingAt end: TimeInterval) -> DetectedSet? {
        defer {
            activeSince = nil
            quietSince = nil
            trimBuffer(before: end)
        }
        guard let begin = activeSince else { return nil }
        let seconds = end - begin
        guard seconds >= Self.minSetSeconds else { return nil }

        let window = buffer.filter { $0.t >= begin && $0.t <= end }
        guard window.count > 8 else { return nil }

        let fs = estimatedRate(of: window)
        guard fs > 0 else { return nil }

        let count = RepCounter.count(sampleRateHz: fs,
                                     x: window.map(\.x),
                                     y: window.map(\.y),
                                     z: window.map(\.z),
                                     exercise: currentRepProfile)
        guard count.reps > 0 else { return nil }

        // Partial data must never be presented as certain.
        let confidence: RepConfidence = droppedForOverflow && count.confidence == .high
            ? .medium : count.confidence

        return DetectedSet(reps: count.reps, confidence: confidence,
                           startedAt: begin, seconds: seconds,
                           repProfile: currentRepProfile)
    }

    private func estimatedRate(of window: [MotionSample]) -> Double {
        var gaps: [Double] = []
        gaps.reserveCapacity(window.count)
        for i in 1..<window.count {
            let d = window[i].t - window[i - 1].t
            if d > 0 { gaps.append(d) }
        }
        guard !gaps.isEmpty else { return 0 }
        gaps.sort()
        let median = gaps[gaps.count / 2]
        return median > 0 ? 1.0 / median : 0
    }

    private func trimBuffer(before cutoff: TimeInterval) {
        guard let first = buffer.first?.t, first < cutoff else { return }
        buffer.removeAll { $0.t < cutoff }
    }
}

/// Where wrist motion comes from.
///
/// The watch implements this with CoreMotion; tests implement it with a
/// generated signal. Keeping it a protocol is what allows the set-detection
/// logic above to be verified without hardware.
public protocol MotionCapturing: AnyObject, Sendable {
    /// True when this device can actually deliver the data.
    var isAvailable: Bool { get }
    /// Begins delivering batches. Pair with `stop()`.
    func start(onBatch: @escaping @Sendable ([MotionSample]) -> Void) throws
    func stop()
}
