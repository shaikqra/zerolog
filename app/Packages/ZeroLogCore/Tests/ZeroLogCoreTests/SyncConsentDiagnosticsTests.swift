import XCTest
@testable import ZeroLogCore

/// Covers the three things added so the watch can be set up, consented to, and
/// debugged in a gym.
final class SyncConsentDiagnosticsTests: XCTestCase {

    // MARK: - Phone to watch settings

    /// The equipment list is a Set<String>, which is not plist-compatible. If it
    /// were put into the application context as a loose value it would be
    /// dropped, and the watch would plan for a gym with no equipment while
    /// looking like it had synced.
    func testSettingsSurviveTheTripToTheWatch() throws {
        let original = UserSettings(equipment: ["barbell", "rack", "dumbbells"],
                                    minutes: 75, unit: .lb)
        let context = try SettingsTransfer.payload(for: original)
        let received = SettingsTransfer.settings(from: context)
        XCTAssertEqual(received, original, "the equipment set must arrive intact")
    }

    /// A malformed context must leave the watch on its previous settings, not
    /// crash and not half-apply.
    func testGarbageContextIsIgnoredRatherThanCrashing() {
        XCTAssertNil(SettingsTransfer.settings(from: [:]))
        XCTAssertNil(SettingsTransfer.settings(from: ["wrong-key": Data()]))
        XCTAssertNil(SettingsTransfer.settings(from: [SettingsTransfer.contextKey: "not data"]))
        XCTAssertNil(SettingsTransfer.settings(
            from: [SettingsTransfer.contextKey: Data("{\"nonsense\":1}".utf8)]))
    }

    // MARK: - Motion consent

    private func tempConsent() -> ConsentStore {
        ConsentStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-consent-\(UUID().uuidString).json"))
    }

    /// Never asked is a different state from asked-and-refused: the first shows
    /// the explanation, the second must not nag.
    func testNeverAskedIsDistinctFromRefused() throws {
        let store = tempConsent()
        XCTAssertTrue(store.load().needsAsking, "a fresh device has not been asked")
        XCTAssertFalse(store.load().allowsCapture)

        try store.save(MotionConsent(granted: false))
        XCTAssertFalse(store.load().needsAsking, "a refusal must not be re-asked")
        XCTAssertFalse(store.load().allowsCapture)

        try store.save(MotionConsent(granted: true))
        XCTAssertTrue(store.load().allowsCapture)
        XCTAssertFalse(store.load().needsAsking)
    }

    /// If what we capture materially changes, old consent no longer covers it.
    func testStaleConsentVersionIsAskedAgain() throws {
        let store = tempConsent()
        try store.save(MotionConsent(granted: true, version: 0))
        let consent = store.load()
        XCTAssertTrue(consent.needsAsking, "consent to an older explanation must be renewed")
        XCTAssertFalse(consent.allowsCapture)
    }

    /// An unreadable file must read as "never asked" rather than as permission.
    func testDamagedConsentFileDefaultsToAsking() throws {
        let store = tempConsent()
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertTrue(store.load().needsAsking)
        XCTAssertFalse(store.load().allowsCapture)
    }

    // MARK: - Diagnostics and session recording

    private func lifting(reps: Int, seconds: Double, from: TimeInterval,
                         hz: Double = 100) -> [MotionSample] {
        let n = Int(seconds * hz)
        return (0..<n).map { i in
            let t = Double(i) / hz
            let phase = 2 * Double.pi * (Double(reps) / seconds) * t
            return MotionSample(t: from + t, x: 0.35 * sin(phase), y: 0, z: 1.0)
        }
    }

    private func resting(seconds: Double, from: TimeInterval, hz: Double = 100) -> [MotionSample] {
        (0..<Int(seconds * hz)).map {
            MotionSample(t: from + Double($0) / hz, x: 0.001, y: 0, z: 1.0)
        }
    }

    func testDiagnosticsReportWhatTheWatchIsActuallySeeing() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        detector.ingest(resting(seconds: 8, from: 25))

        let d = detector.diagnostics
        XCTAssertTrue(d.isCapturing)
        XCTAssertGreaterThan(d.samplesReceived, 3000, "raw sample count, before thinning")
        XCTAssertEqual(d.setsDetected, 1)
        XCTAssertNotNil(d.lastSet)
        // Thinned to ~50 Hz regardless of the 100 Hz input.
        XCTAssertEqual(d.measuredHz, 50, accuracy: 6,
                       "measured rate should reflect the thinned window, got \(d.measuredHz)")
    }

    /// A burst too short to be a set should be counted as a rejected candidate,
    /// not silently vanish. Without this the diagnostics screen cannot
    /// distinguish "saw nothing" from "saw something and threw it away".
    func testRejectedCandidatesAreCounted() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.ingest(lifting(reps: 2, seconds: 2.0, from: 0))
        detector.ingest(resting(seconds: 8, from: 2.0))
        XCTAssertEqual(detector.diagnostics.setsDetected, 0)
        XCTAssertGreaterThan(detector.diagnostics.candidatesRejected, 0,
                             "a rejected burst must be visible, not invisible")
    }

    /// The point of recording: a real workout becomes replayable data, which is
    /// how barbell sets finally get collected.
    func testRecordedSetsKeepTheMotionThatProducedThem() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        detector.ingest(resting(seconds: 8, from: 25))

        XCTAssertEqual(detector.recordedSets.count, 1)
        guard let recorded = detector.recordedSets.first else { return }
        XCTAssertEqual(recorded.repProfile, "squats")
        XCTAssertGreaterThan(recorded.x.count, 100, "the window must be kept for replay")
        XCTAssertEqual(recorded.x.count, recorded.y.count)
        XCTAssertEqual(recorded.x.count, recorded.z.count)
        XCTAssertGreaterThan(recorded.peakEstimate, 0, "both estimators are worth keeping")
        XCTAssertNil(recorded.confirmedReps, "nothing corrected yet")
    }

    func testNothingIsRecordedUnlessAskedFor() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        detector.ingest(resting(seconds: 8, from: 25))
        XCTAssertTrue(detector.recordedSets.isEmpty, "recording must be opt-in")
    }

    /// A user correction is the strongest label available: ground truth from
    /// someone who just did the set.
    func testACorrectionIsAttachedToTheSetItCorrects() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        detector.ingest(resting(seconds: 8, from: 25))
        detector.noteCorrection(reps: 9)
        XCTAssertEqual(detector.recordedSets.last?.confirmedReps, 9)
    }

    func testRecordingIsCappedSoItCannotFillTheWatch() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        var t = 0.0
        for _ in 0..<(SetDetector.maxRecordedSets + 8) {
            detector.ingest(lifting(reps: 10, seconds: 25, from: t))
            detector.ingest(resting(seconds: 8, from: t + 25))
            t += 33
        }
        XCTAssertLessThanOrEqual(detector.recordedSets.count, SetDetector.maxRecordedSets)
    }

    func testResetSessionClearsRecordingAndCounters() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        detector.ingest(lifting(reps: 10, seconds: 25, from: 0))
        detector.ingest(resting(seconds: 8, from: 25))
        XCTAssertFalse(detector.recordedSets.isEmpty)

        detector.resetSession()
        XCTAssertTrue(detector.recordedSets.isEmpty)
        XCTAssertEqual(detector.diagnostics.setsDetected, 0)
        XCTAssertEqual(detector.diagnostics.samplesReceived, 0)
    }

    // MARK: - Session files

    func testSessionsRoundTripAndArePruned() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("zl-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = DiagnosticsStore(folderURL: folder)

        let sets = [RecordedSet(reps: 10, confidence: "high", peakEstimate: 10,
                                autocorrEstimate: 10, sampleRateHz: 50, repProfile: "squats",
                                startedAt: 0, seconds: 25, x: [1, 2], y: [0, 0], z: [1, 1],
                                confirmedReps: nil)]
        try store.save(sets, date: "2026-11-01", sessionType: "legs")
        XCTAssertEqual(try store.load(date: "2026-11-01", sessionType: "legs"), sets)

        for day in 2...9 {
            try store.save(sets, date: "2026-11-0\(day)", sessionType: "legs")
        }
        XCTAssertEqual(store.allSessions().count, 9)
        store.prune(keeping: 5)
        XCTAssertEqual(store.allSessions().count, 5, "old debug data must not fill the watch")
        XCTAssertTrue(store.allSessions().allSatisfy {
            $0.lastPathComponent >= "2026-11-05" }, "the NEWEST sessions should survive")
    }
}
