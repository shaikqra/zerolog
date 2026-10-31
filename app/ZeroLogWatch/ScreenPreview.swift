#if DEBUG
import SwiftUI
import ZeroLogCore

/// Renders ONE watch screen with demo data, chosen by a launch argument.
///
/// Exists because the watch app cannot be photographed any other way. XCUITest
/// does not support watchOS, so there is no automation that can tap through a
/// watch app — and until a paid developer account exists, no real watch can run
/// it either. Without this, every screen on the watch is literally unseen by
/// anyone, including the people building it.
///
/// `xcrun simctl` can install, launch and screenshot a watchOS simulator; what
/// it cannot do is tap. So instead of navigating to a screen, the app is
/// launched straight into it. One launch per screen, one screenshot each.
///
/// Compiled out of release builds. This is a photo studio, not a feature.
enum ScreenPreview {

    static let argumentPrefix = "-previewScreen"

    /// Reads `-previewScreen <name>` from the launch arguments.
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: argumentPrefix),
              index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// A gym with everything, so the planner has a full catalogue to pick from.
    static var demoSettings: UserSettings {
        UserSettings(equipment: ["barbell", "rack", "bench", "dumbbells",
                                 "cable", "pullup_bar", "machine"],
                     minutes: 45, unit: .kg)
    }

    /// A real plan from the real engine. Nothing here is hand-written: if the
    /// planner is wrong, the screenshot shows it being wrong, which is the
    /// entire point of looking.
    static var demoPlan: Workout? {
        guard let catalog = try? Catalog.bundled() else { return nil }
        switch PlanRequest.resolve(catalog: catalog, settings: demoSettings,
                                   history: [], isWatch: true) {
        case .ready(let workout): return workout
        case .needsSetup: return nil
        }
    }

    static var demoActive: ActiveWorkout? {
        guard let plan = demoPlan else { return nil }
        let workout = ActiveWorkout(plan: plan, date: "2026-11-10")
        return workout
    }

    /// A plausible detected set, for the card that asks for a confirmation.
    static var demoDetected: DetectedSet {
        DetectedSet(reps: 9, confidence: .medium, startedAt: 0, seconds: 23,
                    repProfile: demoPlan?.exercises.first?.repProfile)
    }
}

/// The gallery. Each case is one screenshot in `docs/screens/`.
struct ScreenPreviewHost: View {
    let screen: String

    var body: some View {
        switch screen {
        case "start":
            if let plan = ScreenPreview.demoPlan {
                StartView(plan: plan, problem: nil, onStart: {},
                          diagnostics: CaptureDiagnostics(), recordedSets: 0,
                          captureState: "not started")
            } else {
                Text("No plan: the engine returned nothing for a full gym.")
            }

        case "notsetup":
            // The state the watch was stuck in before settings sync existed.
            StartView(plan: nil,
                      problem: "Open ZeroLog on your phone to set up your gym, then come back.",
                      onStart: {}, diagnostics: CaptureDiagnostics(),
                      recordedSets: 0, captureState: "not started")

        case "consent":
            ConsentView(onDecision: { _ in })

        case "set":
            if let active = ScreenPreview.demoActive {
                SetView(workout: active, onConfirm: { _, _ in }, onSkip: {},
                        onEnd: {}, isCapturing: true)
            }

        case "card":
            if let active = ScreenPreview.demoActive {
                SetView(workout: active, onConfirm: { _, _ in }, onSkip: {},
                        onEnd: {}, isCapturing: true)
                    .overlay(alignment: .bottom) {
                        DetectedSetCard(note: "9 reps counted. Tap to log it.",
                                        onUndo: nil, onAccept: {}, onDismiss: {})
                    }
            }

        case "diagnostics":
            // Runs the real self-test, so the screenshot shows actual results
            // from this build rather than a mock-up.
            DiagnosticsPreview()

        case "summary":
            if let active = ScreenPreview.demoActive {
                SummaryView(workout: active, onDone: {})
            }

        default:
            Text("Unknown preview screen: \(screen)")
                .font(.footnote)
        }
    }
}

/// Diagnostics with the self-test already run, since a screenshot cannot tap
/// the button.
private struct DiagnosticsPreview: View {
    @State private var diagnostics: CaptureDiagnostics = {
        var d = CaptureDiagnostics()
        d.isCapturing = true
        d.samplesReceived = 41_250
        d.measuredHz = 50
        d.setsDetected = 3
        d.candidatesRejected = 2
        d.lastSet = DetectedSet(reps: 10, confidence: .high, startedAt: 0,
                                seconds: 21, repProfile: "squats")
        return d
    }()

    var body: some View {
        DiagnosticsView(diagnostics: diagnostics, recordedSets: 3,
                        captureState: "running")
    }
}
#endif
