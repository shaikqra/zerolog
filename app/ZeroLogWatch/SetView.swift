import SwiftUI
import ZeroLogCore

/// The "confirm, don't enter" card. Reps and weight are pre-filled; the user adjusts only if needed
/// (reps with − / +, weight with the Digital Crown) and taps ✓.
/// Once rep detection exists, the detected count replaces the pre-filled reps.
struct SetView: View {
    let workout: ActiveWorkout
    let onConfirm: (Double, Int) -> Void
    let onSkip: () -> Void
    let onEnd: () -> Void

    @State private var weight: Double = 0
    @State private var reps: Int = 0

    /// Starting weight when there's no history: an empty barbell.
    private let defaultWeightKg = 20.0

    var body: some View {
        if let item = workout.current {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Color.plate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Set \(workout.setNumber) of \(item.sets)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack {
                    stepButton("minus", label: "One rep fewer") { reps = max(1, reps - 1) }
                    Text("\(reps)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(reps) reps")
                    stepButton("plus", label: "One more rep") { reps += 1 }
                }

                HStack {
                    Text("\(weight.formatted()) kg")
                        .font(.headline)
                        .monospacedDigit()
                        .focusable()
                        .digitalCrownRotation($weight, from: 0, through: 400, by: item.increment,
                                              sensitivity: .low)
                        .accessibilityLabel("Weight \(weight.formatted()) kilograms. Turn the crown to change.")
                    Spacer()
                    Button {
                        onConfirm(weight, reps)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.plate)
                    .frame(width: 56)
                    .accessibilityLabel("Confirm set")
                }
            }
            .padding(.horizontal, 4)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("End", systemImage: "xmark", action: onEnd)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip exercise", systemImage: "forward.fill", action: onSkip)
                }
            }
            // Refill the pickers whenever a new set starts.
            .task(id: "\(workout.exerciseIndex)-\(workout.setNumber)") {
                weight = workout.suggestedWeight ?? defaultWeightKg
                reps = workout.suggestedReps
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(width: 40, height: 40)
        .accessibilityLabel(label)
    }
}
