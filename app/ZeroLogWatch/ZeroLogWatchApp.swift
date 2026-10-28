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
                }
            } else {
                StartView(plan: controller.plan, problem: controller.problem, onStart: controller.start)
            }
        }
    }
}
