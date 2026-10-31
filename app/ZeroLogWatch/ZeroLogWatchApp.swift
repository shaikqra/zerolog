import SwiftUI

@main
struct ZeroLogWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Picks the screen: consent, start, the set in progress, or the summary.
///
/// @MainActor because the @State initialiser below constructs a main-actor view
/// model, and a View's implicit init is otherwise nonisolated.
@MainActor
struct RootView: View {
    @State private var controller = WorkoutController()

    private var previewScreen: String? {
        #if DEBUG
        return ScreenPreview.requested
        #else
        return nil
        #endif
    }

    var body: some View {
        NavigationStack {
            // DEBUG-only photo studio. The watch app cannot be reached any other
            // way: XCUITest does not support watchOS, and no real watch can run
            // it until the developer account exists.
            if let screen = previewScreen {
                ScreenPreviewHost(screen: screen)
            } else if controller.needsMotionConsent {
                // Asked once, before any movement is read. Refusing still starts
                // the workout -- see WorkoutController.grantMotionConsent.
                ConsentView(onDecision: controller.grantMotionConsent)
            } else if let active = controller.active {
                if active.isFinished {
                    SummaryView(workout: active, onDone: controller.finish)
                } else {
                    SetView(workout: active,
                            onConfirm: controller.confirm,
                            onSkip: controller.skipExercise,
                            onEnd: controller.endEarly,
                            isCapturing: controller.isCapturing)
                        // The card sits over the manual card rather than
                        // replacing it, so the user can always ignore the
                        // automatic count and dial the set in by hand.
                        .overlay(alignment: .bottom) {
                            if let note = controller.loggedAutomatically {
                                DetectedSetCard(note: note,
                                                onUndo: controller.undoAutomaticLog,
                                                onAccept: nil,
                                                onDismiss: controller.dismissCard)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else if let pending = controller.awaitingConfirmation {
                                DetectedSetCard(note: pending.note,
                                                onUndo: nil,
                                                onAccept: controller.acceptPending,
                                                onDismiss: controller.dismissCard)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .animation(.default, value: controller.loggedAutomatically)
                        .animation(.default, value: controller.awaitingConfirmation)
                }
            } else {
                StartView(plan: controller.plan,
                          problem: controller.problem,
                          onStart: controller.start,
                          diagnostics: controller.diagnostics,
                          recordedSets: controller.recordedSetCount,
                          captureState: controller.captureState)
            }
        }
    }
}
