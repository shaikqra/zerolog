import SwiftUI
import ZeroLogCore

/// Today's workout, straight from the engine, with a button to start it.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.plan {
                    List {
                        if let problem = model.problem {
                            Section {
                                Label(problem, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Section {
                            ForEach(plan.exercises, id: \.exerciseId) { item in
                                ExerciseRow(item: item, unit: plan.unit)
                            }
                        } footer: {
                            Text("About \(plan.estimatedMinutes) minutes")
                        }
                        if !plan.skipped.isEmpty {
                            Section("Left out today") {
                                ForEach(plan.skipped, id: \.name) { item in
                                    Text("\(item.name): \(item.reason)")
                                }
                            }
                        }
                    }
                    .navigationTitle("\(plan.sessionType.capitalized) day")
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            model.start()
                        } label: {
                            Text("Start workout")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding()
                        .disabled(plan.exercises.isEmpty)
                    }
                } else {
                    ContentUnavailableView(
                        "Today's workout isn't ready",
                        systemImage: "exclamationmark.triangle",
                        description: Text(model.problem ?? "Reinstall ZeroLog to fix it.")
                    )
                }
            }
            .fullScreenCover(isPresented: workoutIsOpen) {
                WorkoutView()
            }
        }
    }

    private var workoutIsOpen: Binding<Bool> {
        Binding(get: { model.active != nil }, set: { _ in })
    }
}

struct ExerciseRow: View {
    let item: PlannedExercise
    let unit: WeightUnit

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
        let weight = item.weight.map { "\($0.formatted()) \(unit.rawValue)" } ?? "choose weight"
        return "\(item.sets) × \(item.targetReps) · \(weight)"
    }
}
