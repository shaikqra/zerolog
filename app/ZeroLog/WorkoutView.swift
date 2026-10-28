import SwiftUI
import ZeroLogCore

/// Logging a workout on the phone: one set at a time, pre-filled, confirm with one tap.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var weight = 20.0
    @State private var reps = 8

    /// Starting weight when there's no history: an empty barbell (20 kg or 45 lb).
    private func startingWeight(_ unit: WeightUnit) -> Double {
        unit == .lb ? 45 : 20
    }

    var body: some View {
        NavigationStack {
            if let active = model.active {
                if let item = active.current {
                    setForm(active: active, item: item)
                } else {
                    summary(active)
                }
            }
        }
    }

    private func setForm(active: ActiveWorkout, item: PlannedExercise) -> some View {
        Form {
            Section {
                Text(item.name)
                    .font(.title2.bold())
                Text("Set \(active.setNumber) of \(item.sets), aim for \(item.targetReps) reps")
                    .foregroundStyle(.secondary)
                Text(item.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("This set") {
                Stepper(value: $reps, in: 1...50) {
                    LabeledContent("Reps", value: "\(reps)")
                }
                Stepper(value: $weight, in: 0...1000, step: item.increment) {
                    LabeledContent("Weight", value: "\(weight.formatted()) \(active.plan.unit.rawValue)")
                }
            }
        }
        .navigationTitle("\(active.plan.sessionType.capitalized) day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End", action: model.endEarly)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Skip exercise", action: model.skipExercise)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.confirm(weight: weight, reps: reps)
            } label: {
                Label("Confirm set", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        // Refill reps and weight whenever a new set starts.
        .task(id: "\(active.exerciseIndex)-\(active.setNumber)") {
            weight = active.suggestedWeight ?? startingWeight(active.plan.unit)
            reps = active.suggestedReps
        }
    }

    private func summary(_ active: ActiveWorkout) -> some View {
        let anythingLogged = active.totalSetsLogged > 0
        return VStack(spacing: 16) {
            Image(systemName: anythingLogged ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 64))
                .foregroundStyle(Color.plate)
            Text(anythingLogged ? "Workout done" : "Nothing logged")
                .font(.title2.bold())
            if anythingLogged {
                Text("\(active.totalSetsLogged) sets logged. Your next plan builds on them.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(anythingLogged ? "Save workout" : "Close", action: model.finish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
