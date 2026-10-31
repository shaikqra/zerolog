// NOTE THE IMPORT: plain, NOT @testable.
//
// Every other test file uses `@testable import`, which bypasses access control
// entirely — so a type can look perfectly usable in tests and be unbuildable
// from the app. That gap has now broken the macOS build TWICE with the same
// cause: a Swift struct's synthesised memberwise initialiser is INTERNAL even
// when the struct and all of its stored properties are public.
//
// First DetectedSet, then RestAdvice, each costing a full Mac build to learn
// an error Linux could have caught in nine seconds.
//
// This file sees ZeroLogCore exactly as the iPhone and Watch targets see it.
// Anything the app layer constructs must be constructed here too, so the
// failure arrives locally and free.
import XCTest
import ZeroLogCore

final class PublicAPITests: XCTestCase {

    /// The app builds these directly.
    func testTypesTheAppConstructsAreConstructible() {
        let advice = RestAdvice(suggestedSeconds: 150, elapsedSeconds: 30)
        XCTAssertEqual(advice.remainingSeconds, 120)
        XCTAssertEqual(advice.display, "2:00")

        let detected = DetectedSet(reps: 9, confidence: .medium, startedAt: 0,
                                   seconds: 23, repProfile: "squats")
        XCTAssertEqual(detected.reps, 9)
        XCTAssertFalse(detected.isSilentlyLoggable)

        let upcoming = UpcomingSession(sessionType: "pull", position: 1)
        XCTAssertEqual(upcoming.position, 1)

        let summary = ProgressSummary(workoutsThisWeek: 2, setsThisWeek: 9,
                                      volumeThisWeek: 1520, volumeLastWeek: 1000)
        XCTAssertEqual(summary.volumeChangePercent ?? 0, 52, accuracy: 0.5)

        let diagnostics = CaptureDiagnostics()
        XCTAssertFalse(diagnostics.isCapturing)

        let settings = UserSettings(equipment: ["barbell"], minutes: 45, unit: .kg,
                                    bodyweightKg: 78, experience: .returning)
        XCTAssertEqual(settings.experience, .returning)

        let address = SetAddress(session: 0, exercise: 1, set: 2)
        XCTAssertEqual(address.set, 2)

        let sample = MotionSample(t: 0, x: 0, y: 0, z: 1)
        XCTAssertEqual(sample.z, 1)

        let consent = MotionConsent(granted: true)
        XCTAssertTrue(consent.allowsCapture)

        let logged = LoggedSet(weightKg: 60, reps: 10)
        let exercise = LoggedExercise(exerciseId: "bench_press", sets: [logged])
        let session = Session(date: "2026-11-09", sessionType: "push", exercises: [exercise])
        XCTAssertEqual(session.exercises.first?.sets.first?.reps, 10)
    }

    /// The entry points the app calls. If any of these stopped being public the
    /// app would not build, and only a Mac would say so.
    func testEntryPointsTheAppCallsArePublic() throws {
        let catalog = try Catalog.bundled()
        let gym: Set<String> = ["barbell", "rack", "bench", "dumbbells"]

        let plan = Engine.generateWorkout(catalog: catalog, gymEquipment: gym,
                                          minutes: 45, history: [],
                                          bodyweightKg: 78, experience: .novice)
        XCTAssertFalse(plan.exercises.isEmpty)

        // Properties the UI reads off a planned exercise.
        let item = try XCTUnwrap(plan.exercises.first)
        XCTAssertGreaterThan(item.restSeconds, 0)
        _ = item.name
        _ = item.reason
        _ = item.targetReps
        _ = item.increment
        _ = item.detectable
        _ = item.previousWeight
        _ = item.change

        _ = Engine.upcoming(catalog: catalog, history: [], count: 3)
        _ = Engine.undoChange(plan, exerciseId: item.exerciseId)
        _ = Progress.summary(history: [], today: "2026-11-09")
        _ = RestTimer.advice(kind: "compound", secondsSinceSet: 10)
        _ = PlanRequest.resolve(catalog: catalog, settings: nil, history: [], isWatch: true)
        _ = SelfTest.run()
        _ = UserSettings.parseBodyweight("78", unit: .kg)

        let movement = try XCTUnwrap(catalog.exercises.first { $0.startRatio != nil })
        _ = StartingWeight.suggest(for: movement, bodyweightKg: 78,
                                   experience: .novice, unit: .kg)
        _ = StartingWeight.reason(target: 8, unit: .kg)

        var active = ActiveWorkout(plan: plan, date: "2026-11-09")
        _ = active.confirmSet(weight: 60, reps: 10)
        _ = active.undoLastSet()
        active.skipExercise()
        active.endEarly()
        _ = active.isFinished
        _ = active.current
        _ = active.suggestedWeight
        _ = active.totalSetsLogged

        let history = [Session(date: "2026-11-09", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press", sets: [LoggedSet(weightKg: 60, reps: 10)])
        ])]
        let address = SetAddress(session: 0, exercise: 0, set: 0)
        _ = HistoryEdit.read(history, at: address)
        _ = HistoryEdit.update(history, at: address, weightKg: 62.5, reps: 8)
        _ = HistoryEdit.delete(history, at: address)
        _ = HistoryEdit.describeDelete(history, at: address, unit: .kg)
    }

    /// The watch builds these.
    func testWatchFacingAPIIsPublic() {
        let detector = SetDetector(currentRepProfile: "squats")
        detector.recordsWindows = true
        _ = detector.ingest([MotionSample(t: 0, x: 0, y: 0, z: 1)])
        _ = detector.flush()
        _ = detector.diagnostics
        _ = detector.recordedSets
        detector.noteCorrection(reps: 9)
        detector.resetSession()
        detector.reset()
        detector.currentRepProfile = "bicep_curls"
        _ = detector.bufferedSampleCount

        _ = AutoLog.decide(detected: DetectedSet(reps: 10, confidence: .high, startedAt: 0,
                                                 seconds: 20, repProfile: nil),
                           exercise: nil, suggestedWeight: nil, unit: .kg)
        _ = RepCounter.count(sampleRateHz: 50, x: [0], y: [0], z: [1], exercise: nil)
        _ = SettingsTransfer.settings(from: [:])
    }
}
