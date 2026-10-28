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
                        let changes = plan.exercises.filter { $0.change != nil }
                        if !changes.isEmpty {
                            Section("What I changed") {
                                ForEach(changes, id: \.exerciseId) { item in
                                    ChangeRow(item: item, unit: plan.unit) { model.undoChange(item.exerciseId) }
                                }
                            }
                        }
                        Section {
                            ForEach(plan.exercises, id: \.exerciseId) { item in
                                NavigationLink {
                                    HowToView(exerciseId: item.exerciseId)
                                } label: {
                                    ExerciseRow(item: item, unit: plan.unit)
                                }
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
                    .textCase(nil)
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

    /// "3 × 6 at 62.5 kg", or "3 × 6, choose a weight" the first time.
    private var prescription: String {
        let sets = "\(item.sets) × \(item.targetReps)"
        guard let weight = item.weight else { return "\(sets), choose a weight" }
        return "\(sets) at \(weight.formatted()) \(unit.rawValue)"
    }
}

/// One weight change the engine made, why, and an Undo.
struct ChangeRow: View {
    let item: PlannedExercise
    let unit: WeightUnit
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(item.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo", action: undo)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    /// "Added 5 lb to Barbell bench press" or "Lightened Barbell bench press to 120 lb".
    private var title: String {
        guard let weight = item.weight, let previous = item.previousWeight else { return item.name }
        switch item.change {
        case .increased: return "Added \((weight - previous).formatted()) \(unit.rawValue) to \(item.name)"
        case .deloaded: return "Lightened \(item.name) to \(weight.formatted()) \(unit.rawValue)"
        case nil: return item.name
        }
    }
}
