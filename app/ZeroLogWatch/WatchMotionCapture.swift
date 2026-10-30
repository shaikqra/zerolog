import CoreMotion
import Foundation
import ZeroLogCore

/// Streams wrist acceleration from the watch into `SetDetector`.
///
/// UNVERIFIED ON HARDWARE. CoreMotion does not exist in the Linux toolchain, so
/// unlike everything in ZeroLogCore this file has never been compiled or run.
/// It is kept deliberately thin -- all the decision logic lives in
/// `SetDetector`, which is tested -- so that what needs checking on a real watch
/// is just "do samples arrive, at what rate, and at what battery cost".
///
/// Two paths, because one API is newer than the watches people own:
///
/// - `CMBatchedSensorManager` is the API built for this exact job (high-rate
///   batched accelerometer during a workout). It needs Apple Watch Series 8 or
///   newer, or an Ultra.
/// - `CMMotionManager` device motion at 100 Hz covers older watches. Reps live
///   below 2 Hz, so 100 Hz is still far more than the counter needs.
///
/// `NSMotionUsageDescription` MUST be present in the watch target's Info.plist.
/// Raw accelerometer streams expose no permission-request API, so without the
/// string the app does not get a denial -- it crashes on first access.
final class WatchMotionCapture: MotionCapturing, @unchecked Sendable {

    private let batched = CMBatchedSensorManager()
    /// Exactly one CMMotionManager per app: competing instances cut the sample rate.
    private let fallback = CMMotionManager()
    private var task: Task<Void, Never>?
    private var started = false

    /// First timestamp seen, so everything downstream is session-relative.
    ///
    /// PRIVACY, not tidiness: `CMLogItem.timestamp` is seconds since boot.
    /// Turning it into a wall-clock date reads system boot time, a
    /// required-reason API -- and under reason `35F9.1` that value may never
    /// leave the device. Subtracting the first sample's timestamp sidesteps the
    /// whole question, so no boot time is ever derived, stored or transmitted.
    private var epoch: TimeInterval?

    private var useBatched: Bool {
        CMBatchedSensorManager.isAccelerometerSupported
            && CMBatchedSensorManager.authorizationStatus != .denied
            && CMBatchedSensorManager.authorizationStatus != .restricted
    }

    var isAvailable: Bool { useBatched || fallback.isDeviceMotionAvailable }

    /// Sample rate the hardware actually chose. Read-only, and only meaningful
    /// after `start()`; `SetDetector` derives rate from timestamps anyway, so
    /// this is for diagnostics rather than for the maths.
    /// NOTE: `accelerometerDataFrequency` is an **Int**, not a Double. Assuming
    /// otherwise failed the watchOS build.
    var reportedHz: Double {
        useBatched
            ? Double(batched.accelerometerDataFrequency)
            : 1.0 / max(fallback.deviceMotionUpdateInterval, .ulpOfOne)
    }

    func start(onBatch: @escaping @Sendable ([MotionSample]) -> Void) throws {
        guard !started else { return }
        guard isAvailable else { throw MotionCaptureError.unavailable }
        started = true
        epoch = nil

        if useBatched {
            startBatched(onBatch: onBatch)
        } else {
            try startFallback(onBatch: onBatch)
        }
    }

    private func startBatched(onBatch: @escaping @Sendable ([MotionSample]) -> Void) {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await batch in self.batched.accelerometerUpdates() {
                    if Task.isCancelled { break }
                    var out: [MotionSample] = []
                    out.reserveCapacity(batch.count)
                    for sample in batch {
                        if self.epoch == nil { self.epoch = sample.timestamp }
                        let a = sample.acceleration
                        out.append(MotionSample(t: sample.timestamp - (self.epoch ?? sample.timestamp),
                                                x: a.x, y: a.y, z: a.z))
                    }
                    if !out.isEmpty { onBatch(out) }
                }
            } catch {
                // A thrown error ends the stream; the caller sees samples stop.
                // Deliberately silent: there is nothing the user can do, and a
                // half-counted set must not be presented as a real one.
            }
        }
    }

    private func startFallback(onBatch: @escaping @Sendable ([MotionSample]) -> Void) throws {
        guard fallback.isDeviceMotionAvailable else { throw MotionCaptureError.unavailable }
        fallback.deviceMotionUpdateInterval = 1.0 / 100.0

        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryCorrectedZVertical)
            ? .xArbitraryCorrectedZVertical
            : .xArbitraryZVertical

        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1

        fallback.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            if self.epoch == nil { self.epoch = motion.timestamp }
            // userAcceleration is gravity-removed and in g, which is what the
            // counter's band-pass expects. Gravity would be filtered out anyway.
            let a = motion.userAcceleration
            onBatch([MotionSample(t: motion.timestamp - (self.epoch ?? motion.timestamp),
                                  x: a.x, y: a.y, z: a.z)])
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if useBatched {
            batched.stopAccelerometerUpdates()
        } else {
            fallback.stopDeviceMotionUpdates()
        }
        started = false
    }
}

enum MotionCaptureError: Error {
    case unavailable
}
