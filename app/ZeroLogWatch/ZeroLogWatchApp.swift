import SwiftUI

@main
struct ZeroLogWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Picks the screen: start, the set in progress, or the summary.
struct RootView: View {
    @State private var controller = WorkoutController()

    var body: some View {
        NavigationStack {
            if let active = controller.active {
                if active.isFinished {
                    SummaryView(workout: active, onDone: controller.finish)
                } else {
                    SetView(workout: active,
                            onConfirm: controller.confirm,
                            onSkip: controller.skipExercise,
                            onEnd: controller.endEarly)
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
                StartView(plan: controller.plan, problem: controller.problem, onStart: controller.start)
            }
        }
    }
}
