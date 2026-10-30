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
public final class SetDetector: @unchecked Sendable {

    /// Guards every piece of mutable state below.
    ///
    /// Needed because samples arrive off the main actor -- CoreMotion delivers
    /// them on its own queue or Task -- while the exercise is set from the UI on
    /// the main actor. Swift 6 rejects reaching main-actor state from a
    /// `@Sendable` closure, and it is right to: the two really do race.
    ///
    /// A lock rather than an actor so `ingest` stays synchronous. The capture
    /// callback has nowhere to await, and making it async would mean buffering
    /// samples somewhere else instead -- the same problem, moved.
    private let lock = NSLock()

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

    /// Energy is measured over a window this long, stepped every second.
    ///
    /// Must be LONGER than the slowest plausible rep or slow lifting reads as
    /// rest. A one-second window was the original choice and it was wrong: a
    /// grindy squat at three seconds per rep spends whole seconds barely
    /// moving, so a 1 s window lands inside the slow phase, scores as quiet,
    /// and splits one set into two. Three seconds comfortably covers reps down
    /// to about 0.33 Hz, which is slower than anyone grinds out a single.
    static let energyWindowSeconds: Double = 3.0
    static let energyStepSeconds: Double = 1.0

    /// Shorter bursts than this are racking the weight, not a set.
    public static let minSetSeconds: Double = 4.0

    /// Hard cap on buffered samples, so a watch left recording cannot grow
    /// without bound. 50 Hz x 300 s is a five-minute set, far beyond real.
    static let maxBufferedSamples = Int(targetHz * 300)

    // MARK: State

    /// Which exercise the engine says is next. Set this BEFORE the set happens:
    /// per-exercise calibration is the only defence against both estimators
    /// agreeing on a wrong number.
    public var currentRepProfile: String? {
        get { lock.withLock { _currentRepProfile } }
        set { lock.withLock { _currentRepProfile = newValue } }
    }

    private var _currentRepProfile: String?

    /// When on, each counted set is kept with the motion that produced it, so a
    /// real workout can be replayed through the tuner offline. This is how the
    /// barbell data finally gets collected: as a by-product of using the app.
    public var recordsWindows: Bool {
        get { lock.withLock { _recordsWindows } }
        set { lock.withLock { _recordsWindows = newValue } }
    }

    private var _recordsWindows = false
    private var recorded: [RecordedSet] = []
    private var samplesSeen = 0
    private var setsDetected = 0
    private var candidatesRejected = 0
    private var lastMeasuredHz: Double = 0
    private var lastSet: DetectedSet?

    /// Capped because this is debugging data on a device with little storage.
    /// It must never be the reason a workout cannot be saved.
    static let maxRecordedSets = 40

    private var buffer: [MotionSample] = []
    private var lastKeptTime: TimeInterval?
    /// Rolling tail of kept samples, trimmed to `energyWindowSeconds`.
    private var windowSamples: [MotionSample] = []
    private var lastEvaluated: TimeInterval?
    private var activeSince: TimeInterval?
    private var quietSince: TimeInterval?
    private var droppedForOverflow = false

    public init(currentRepProfile: String? = nil) {
        self._currentRepProfile = currentRepProfile
    }

    // MARK: Input

    /// Feeds a batch of samples in and returns any sets that completed.
    ///
    /// Returns an array because one batch can, in principle, close more than one
    /// set -- a caller that resumes after a gap should not silently lose data.
    @discardableResult
    public func ingest(_ samples: [MotionSample]) -> [DetectedSet] {
        lock.withLock { ingestLocked(samples) }
    }

    private func ingestLocked(_ samples: [MotionSample]) -> [DetectedSet] {
        var finished: [DetectedSet] = []
        samplesSeen += samples.count
        for sample in samples {
            // 1. Thin to targetHz, using timestamps rather than assuming a rate.
            //
            // The 0.999 is not noise. Comparing against the exact interval drops
            // one extra sample whenever the input rate is a clean multiple of
            // the target: at 100 Hz, `0.02 - 0.0` computes just under 0.02 in
            // floating point, so that sample is skipped and the next one lands
            // 0.03 apart -- yielding 33 Hz where the code claims 50. Accuracy
            // survived either way, but the effective rate should match the
            // documented intent rather than drift below it.
            if let last = lastKeptTime,
               sample.t - last < 0.999 / Self.targetHz { continue }
            lastKeptTime = sample.t

            buffer.append(sample)
            if buffer.count > Self.maxBufferedSamples {
                buffer.removeFirst(buffer.count - Self.maxBufferedSamples)
                droppedForOverflow = true
            }

            // 2. Classify work vs rest over a ROLLING window, stepped each second.
            windowSamples.append(sample)
            let cutoff = sample.t - Self.energyWindowSeconds
            if let first = windowSamples.first?.t, first < cutoff {
                windowSamples.removeAll { $0.t < cutoff }
            }

            if lastEvaluated == nil { lastEvaluated = sample.t }
            guard let previous = lastEvaluated,
                  sample.t - previous >= Self.energyStepSeconds else { continue }
            lastEvaluated = sample.t

            let energy = (0..<3)
                .map { axis in RepCounter.standardDeviation(windowSamples.map { $0.axes[axis] }) }
                .reduce(0, +) / 3.0
            let windowEnd = sample.t
            // The window looks BACK, so movement in it began at least this early.
            let windowStart = max(windowEnd - Self.energyWindowSeconds, 0)

            if energy > Self.activeThresholdG {
                if activeSince == nil { activeSince = windowStart }
                quietSince = nil
            } else if activeSince != nil {
                if quietSince == nil { quietSince = windowEnd }
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
        lock.withLock {
            guard activeSince != nil, let last = buffer.last?.t else { return nil }
            return closeSet(endingAt: last)
        }
    }

    public func reset() {
        lock.withLock { resetLocked() }
    }

    /// Clears everything, including recorded sets. For a NEW workout.
    public func resetSession() {
        lock.withLock {
            resetLocked()
            recorded.removeAll()
            samplesSeen = 0
            setsDetected = 0
            candidatesRejected = 0
            lastMeasuredHz = 0
            lastSet = nil
        }
    }

    private func resetLocked() {
        buffer.removeAll()
        windowSamples.removeAll()
        lastKeptTime = nil
        lastEvaluated = nil
        activeSince = nil
        quietSince = nil
        droppedForOverflow = false
    }

    /// True when samples were discarded to respect the memory cap, which means
    /// the next count covers less than the whole set. Surface it rather than
    /// reporting a confident number from partial data.
    public var didDropSamples: Bool { lock.withLock { droppedForOverflow } }

    /// Exposed so a test can prove the buffer stays capped.
    public var bufferedSampleCount: Int { lock.withLock { buffer.count } }

    /// Live numbers for the diagnostics screen.
    public var diagnostics: CaptureDiagnostics {
        lock.withLock {
            var d = CaptureDiagnostics()
            d.isCapturing = samplesSeen > 0
            d.samplesReceived = samplesSeen
            d.measuredHz = lastMeasuredHz
            d.setsDetected = setsDetected
            d.candidatesRejected = candidatesRejected
            d.lastSet = lastSet
            d.droppedSamples = droppedForOverflow
            return d
        }
    }

    /// Sets recorded this session, for export. Empty unless `recordsWindows`.
    public var recordedSets: [RecordedSet] { lock.withLock { recorded } }

    /// Attaches the user's correction to the most recent recorded set.
    ///
    /// An explicit correction is the strongest label we can get: it says what
    /// the set really was, from someone who just did it. Far better evidence
    /// than a silent acceptance.
    public func noteCorrection(reps: Int) {
        lock.withLock {
            guard !recorded.isEmpty else { return }
            recorded[recorded.count - 1].confirmedReps = reps
        }
    }

    // MARK: Counting

    private func closeSet(endingAt end: TimeInterval) -> DetectedSet? {
        defer {
            activeSince = nil
            quietSince = nil
            trimBuffer(before: end)
        }
        guard let begin = activeSince else { return nil }
        let seconds = end - begin
        guard seconds >= Self.minSetSeconds else {
            candidatesRejected += 1
            return nil
        }

        let window = buffer.filter { $0.t >= begin && $0.t <= end }
        guard window.count > 8 else {
            candidatesRejected += 1
            return nil
        }

        let fs = estimatedRate(of: window)
        guard fs > 0 else {
            candidatesRejected += 1
            return nil
        }
        lastMeasuredHz = fs

        let count = RepCounter.count(sampleRateHz: fs,
                                     x: window.map(\.x),
                                     y: window.map(\.y),
                                     z: window.map(\.z),
                                     exercise: _currentRepProfile)
        guard count.reps > 0 else {
            candidatesRejected += 1
            return nil
        }

        // Partial data must never be presented as certain.
        let confidence: RepConfidence = droppedForOverflow && count.confidence == .high
            ? .medium : count.confidence

        let set = DetectedSet(reps: count.reps, confidence: confidence,
                              startedAt: begin, seconds: seconds,
                              repProfile: _currentRepProfile)
        setsDetected += 1
        lastSet = set

        if _recordsWindows && recorded.count < Self.maxRecordedSets {
            recorded.append(RecordedSet(
                reps: set.reps, confidence: set.confidence.rawValue,
                peakEstimate: count.peakEstimate, autocorrEstimate: count.autocorrEstimate,
                sampleRateHz: fs, repProfile: _currentRepProfile,
                startedAt: begin, seconds: seconds,
                x: window.map(\.x), y: window.map(\.y), z: window.map(\.z),
                confirmedReps: nil))
        }
        return set
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
