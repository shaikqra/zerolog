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
                        Text(summary(plan))
                            .font(.ui(17))
                            .foregroundStyle(Color.textSecondary)
                            .listRowBackground(Color.clear)
                        if let problem = model.problem {
                            Section {
                                Label(problem, systemImage: "exclamationmark.triangle")
                                    .font(.ui(16))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .listRowBackground(Color.surface)
                        }
                        let changes = plan.exercises.filter { $0.change != nil }
                        if !changes.isEmpty {
                            Section {
                                ForEach(changes, id: \.exerciseId) { item in
                                    ChangeRow(item: item, unit: plan.unit) { model.undoChange(item.exerciseId) }
                                }
                            } header: {
                                SectionTitle("What I changed")
                            }
                            .listRowBackground(Color.surface)
                        }
                        Section {
                            ForEach(plan.exercises, id: \.exerciseId) { item in
                                NavigationLink {
                                    HowToView(exerciseId: item.exerciseId)
                                } label: {
                                    ExerciseRow(item: item, unit: plan.unit)
                                }
                            }
                        } header: {
                            SectionTitle("Today's plan")
                        }
                        .listRowBackground(Color.surface)
                        if !plan.skipped.isEmpty {
                            Section {
                                ForEach(plan.skipped, id: \.name) { item in
                                    Text("\(item.name): \(item.reason)")
                                        .font(.ui(15))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            } header: {
                                SectionTitle("Left out today")
                            }
                            .listRowBackground(Color.surface)
                        }
                    }
                    .darkList()
                    .navigationTitle("\(plan.sessionType.capitalized) day")
                    .safeAreaInset(edge: .bottom) {
                        Button("Start workout", action: model.start)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(20)
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

    /// "4 moves, about 38 minutes."
    private func summary(_ plan: Workout) -> String {
        let moves = plan.exercises.count == 1 ? "1 move" : "\(plan.exercises.count) moves"
        return "\(moves), about \(plan.estimatedMinutes) minutes."
    }
}

struct ExerciseRow: View {
    let item: PlannedExercise
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.ui(18, bold: true))
                .foregroundStyle(Color.textPrimary)
            Text(prescription)
                .font(.score(28, relativeTo: .title2))
                .foregroundStyle(Color.load)
            Text(item.reason)
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 6)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ui(17, bold: true))
                .foregroundStyle(Color.textPrimary)
            Text(item.reason)
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
            Button("Undo", action: undo)
                .buttonStyle(OutlineButtonStyle())
        }
        .padding(.vertical, 6)
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
