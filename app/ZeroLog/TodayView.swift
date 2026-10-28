import SwiftUI
import ZeroLogCore

/// Today's workout, straight from the engine.
struct TodayView: View {
    private let workout = SampleData.todaysWorkout()

    var body: some View {
        NavigationStack {
            if let workout {
                List {
                    Section {
                        ForEach(workout.exercises, id: \.exerciseId) { item in
                            ExerciseRow(item: item)
                        }
                    } footer: {
                        Text("About \(workout.estimatedMinutes) minutes")
                    }

                    if !workout.skipped.isEmpty {
                        Section("Left out today") {
                            ForEach(workout.skipped, id: \.name) { item in
                                Text("\(item.name): \(item.reason)")
                            }
                        }
                    }
                }
                .navigationTitle("\(workout.sessionType.capitalized) day")
            } else {
                ContentUnavailableView(
                    "Today's workout didn't load",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The exercise list is missing. Reinstall ZeroLog to fix it.")
                )
            }
        }
        .tint(.plate)
    }
}

struct ExerciseRow: View {
    let item: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            Text(prescription)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.plate)
            Text(item.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// "3 × 6 · 62.5 kg", or "3 × 6 · choose weight" the first time.
    private var prescription: String {
        let weight = item.weightKg.map { "\($0.formatted()) kg" } ?? "choose weight"
        return "\(item.sets) × \(item.targetReps) · \(weight)"
    }
}

#Preview {
    TodayView()
}
