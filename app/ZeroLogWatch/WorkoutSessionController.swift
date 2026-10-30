import Foundation
import HealthKit
import ZeroLogCore

/// Keeps the watch app running while the user lifts, so motion capture does not
/// stop the moment their wrist drops.
///
/// UNVERIFIED ON HARDWARE: HealthKit is absent from the Linux toolchain, so this
/// file has never been compiled. The logic it feeds (`SetDetector`) is tested;
/// this is the plumbing that needs a real watch.
///
/// Why a workout session is not optional: without one, watchOS suspends the app
/// within seconds of the user lowering their arm, accelerometer updates stop,
/// and the set is lost. `HKWorkoutSession` is what grants an app permission to
/// keep sampling for the length of a workout.
///
/// It also helps on compliance. Guideline 2.5.14 requires continuous motion
/// recording to be obvious to the user; an active workout session shows the
/// system's own workout indicator, which is exactly that signal. It does not
/// replace asking for consent before the first capture.
///
/// Required project configuration:
///   - HealthKit capability on the watch target
///   - `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`
///   - `NSMotionUsageDescription` (missing it CRASHES rather than denying)
@MainActor
final class WorkoutSessionController: NSObject {

    enum State: Equatable {
        case idle
        case running
        /// Carries words fit to show the user.
        case failed(String)
    }

    private(set) var state: State = .idle

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let capture: any MotionCapturing
    /// nonisolated because samples arrive off the main actor. SetDetector guards
    /// its own state with a lock, which is what makes this safe rather than just
    /// quiet -- Swift 6 would reject the main-actor version outright.
    private nonisolated let detector: SetDetector

    /// Called on the main actor for every set the watch spots by itself.
    private let onSetDetected: @MainActor (DetectedSet) -> Void

    init(capture: any MotionCapturing = WatchMotionCapture(),
         detector: SetDetector = SetDetector(),
         onSetDetected: @escaping @MainActor (DetectedSet) -> Void) {
        self.capture = capture
        self.detector = detector
        self.onSetDetected = onSetDetected
        super.init()
    }

    /// Throws away motion buffered for a set that has NOT been closed yet.
    ///
    /// Needed because logging a set by hand does not tell the detector anything.
    /// Without this, a user who taps confirm mid-set gets the set recorded
    /// twice: once by their tap, then again four seconds later when stillness
    /// closes the same physical set. Same for skipping an exercise, where the
    /// buffered motion would otherwise be attributed to the next one.
    func discardInProgressSet() {
        detector.reset()
    }

    /// The exercise the engine planned next, so the right calibration is used.
    /// Must be set BEFORE the set happens -- per-exercise calibration is the
    /// only guard against both rep estimators agreeing on a wrong number.
    func setCurrentExercise(repProfile: String?) {
        detector.currentRepProfile = repProfile
    }

    // MARK: Lifecycle

    func start() async {
        guard state != .running else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("This watch can't record workouts.")
            return
        }
        guard capture.isAvailable else {
            // Honest, and it matters for Guideline 5.1.1(ii): the app has to
            // remain useful when motion is unavailable or refused.
            state = .failed("Automatic rep counting isn't available on this watch. You can still log sets by hand.")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            // Only what is actually used. Over-requesting is an App Review risk.
            let share: Set<HKSampleType> = [HKObjectType.workoutType()]
            let read: Set<HKObjectType> = [HKObjectType.workoutType()]
            try await healthStore.requestAuthorization(toShare: share, read: read)

            let session = try HKWorkoutSession(healthStore: healthStore,
                                               configuration: configuration)
            session.delegate = self
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: configuration)
            self.session = session
            self.builder = builder

            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())

            try capture.start { [weak self] batch in
                // Counting runs off the main actor; only finished sets hop back.
                guard let self else { return }
                let finished = self.detector.ingest(batch)
                guard !finished.isEmpty else { return }
                Task { @MainActor in
                    for set in finished { self.onSetDetected(set) }
                }
            }
            state = .running
        } catch {
            state = .failed("Couldn't start tracking. You can still log sets by hand.")
            capture.stop()
            session = nil
            builder = nil
        }
    }

    /// Asks the session to stop. Teardown happens in the delegate's `.stopped`
    /// transition, NOT here -- calling endCollection immediately after
    /// stopActivity loses data.
    func requestStop() {
        capture.stop()
        // The last set has no trailing stillness to close it, so close it here
        // or it is silently dropped.
        if let last = detector.flush() { onSetDetected(last) }
        guard let session else {
            state = .idle
            return
        }
        session.stopActivity(with: Date())
    }

    private func finishAfterStopped() async {
        guard let builder else {
            state = .idle
            return
        }
        do {
            try await builder.endCollection(at: Date())
            // A nil workout while the device is locked is not a failure.
            _ = try await builder.finishWorkout()
        } catch {
            state = .failed("The workout was recorded but couldn't be saved to Health.")
        }
        self.session = nil
        self.builder = nil
        detector.reset()
        if state == .running { state = .idle }
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        guard toState == .stopped else { return }
        Task { @MainActor in await self.finishAfterStopped() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {
        Task { @MainActor in
            self.capture.stop()
            self.state = .failed("Tracking stopped unexpectedly. Your logged sets are safe.")
        }
    }
}
