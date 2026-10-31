import SwiftUI
import ZeroLogCore

/// The "confirm, don't enter" card. Reps and weight are pre-filled; the user adjusts only if needed
/// (reps with − / +, weight with the Digital Crown) and taps ✓.
/// Once rep detection exists, the detected count replaces the pre-filled reps.
struct SetView: View {
    let workout: ActiveWorkout
    let onConfirm: @MainActor (Double, Int) -> Void
    let onSkip: @MainActor () -> Void
    let onEnd: @MainActor () -> Void
    /// Drives the recording indicator guideline 2.5.14 asks for.
    var isCapturing: Bool = false

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    /// True when the watch has dimmed to the Always On display.
    ///
    /// This is NOT an edge case for ZeroLog -- it is the state the app is in
    /// during the most important moment it has. Mid-set the wrist is under a
    /// barbell, not raised to read a screen, so the dimmed view is what a
    /// lifter actually glances at between reps. It gets the rep count large
    /// and drops everything else, which is also the lower-power path.
    @Environment(\.isLuminanceReduced) private var isDimmed

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
                HStack(spacing: 6) {
                    Text("Set \(workout.setNumber) of \(item.sets)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // Guideline 2.5.14 wants the recording indicator visible
                    // WHENEVER sensors are being read, and the watch is still
                    // reading them while dimmed -- so this stays in both
                    // states rather than being treated as chrome.
                    if isCapturing {
                        RecordingIndicator()
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    // The steppers are touch targets, and the screen is not
                    // accepting touches while dimmed. Hiding them gives the
                    // count the full width instead of framing it with two
                    // controls nobody can press.
                    if !isDimmed {
                        stepButton("minus", label: "One rep fewer") { reps = max(1, reps - 1) }
                    }
                    Text("\(reps)")
                        .font(.system(size: isDimmed ? 52 : 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(reps) reps")
                    if !isDimmed {
                        stepButton("plus", label: "One more rep") { reps += 1 }
                    }
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
