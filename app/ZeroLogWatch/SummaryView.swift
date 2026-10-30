import SwiftUI
import ZeroLogCore

struct SummaryView: View {
    let workout: ActiveWorkout
    let onDone: @MainActor () -> Void

    private var anythingLogged: Bool { workout.totalSetsLogged > 0 }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: anythingLogged ? "checkmark.circle.fill" : "circle.dashed")
                .font(.largeTitle)
                .foregroundStyle(Color.plate)
            Text(anythingLogged ? "Workout done" : "Nothing logged")
                .font(.headline)
            if anythingLogged {
                Text("\(workout.totalSetsLogged) sets logged")
                    .foregroundStyle(.secondary)
            }
            Button(anythingLogged ? "Save workout" : "Close", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.plate)
        }
    }
}
