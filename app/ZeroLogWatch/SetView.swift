import SwiftUI
import ZeroLogCore

/// The "confirm, don't enter" card. For now it shows the first planned exercise;
/// detected reps replace the target once rep detection exists.
struct SetView: View {
    private let item = SampleData.todaysWorkout()?.exercises.first
    @State private var confirmed = false

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Color.plate)
                Text("Set 1 of \(item.sets)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(item.targetReps)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("reps")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(confirmed ? "Logged" : weightPrompt(item))
                        .font(.headline)
                    Spacer()
                    Button {
                        confirmed = true
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.plate)
                    .disabled(confirmed)
                    .accessibilityLabel("Confirm set")
                }
            }
            .padding(.horizontal)
        } else {
            Text("Today's workout didn't load. Reinstall ZeroLog to fix it.")
        }
    }

    private func weightPrompt(_ item: PlannedExercise) -> String {
        item.weightKg.map { "\($0.formatted()) kg?" } ?? "Weight?"
    }
}

#Preview {
    SetView()
}
