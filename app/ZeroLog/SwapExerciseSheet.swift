import SwiftUI
import ZeroLogCore

/// "The rack is taken" — pick a different movement for this slot.
///
/// Only offered before any set is logged against the exercise. Once you have
/// lifted, those sets belong to that movement and reassigning them would make
/// the record a lie.
struct SwapExerciseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let currentName: String

    var body: some View {
        NavigationStack {
            Group {
                let options = model.swapOptions()
                if options.isEmpty {
                    // Says WHY there is nothing, and what would change it.
                    // "No alternatives" alone reads like a broken screen.
                    ContentUnavailableView {
                        Label("No swap available", systemImage: "arrow.triangle.swap")
                    } description: {
                        Text("Nothing else in your gym trains the same movement as \(currentName). Adding equipment in Settings may open up more options.")
                    }
                } else {
                    List(options, id: \.id) { exercise in
                        Button {
                            model.swapCurrentExercise(to: exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.ui(17, bold: true))
                                    .foregroundStyle(Color.textPrimary)
                                Text(lastTimeText(for: exercise))
                                    .font(.ui(14))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.surface)
                    }
                    .darkList()
                }
            }
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Tells the lifter what they will be starting from, so a swap is not a
    /// jump into the dark. A movement they have never done says so plainly
    /// rather than showing a confident-looking blank.
    private func lastTimeText(for exercise: Exercise) -> String {
        let unit = model.active?.plan.unit ?? .kg
        let planned = ExerciseSwap.plan(exercise, history: model.history, unit: unit,
                                        bodyweightKg: model.settings?.bodyweightKg,
                                        experience: model.settings?.experience ?? .novice)
        guard let weight = planned.weight else {
            return "First time — you will pick the weight"
        }
        return "Start at \(weight.formatted()) \(unit.rawValue)"
    }
}
