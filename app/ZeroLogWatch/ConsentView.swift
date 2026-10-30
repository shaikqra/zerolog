import SwiftUI
import ZeroLogCore

/// Asks before reading the user's wrist movement.
///
/// Required by App Store guideline 2.5.14, which wants explicit consent for
/// continuous motion recording. It is also simply the right thing to ask.
///
/// Written to be refusable without punishment. Saying no leaves manual logging
/// fully working, which guideline 5.1.1(ii) also requires: paid functionality
/// must not depend on granting a sensor permission. So the copy offers a real
/// choice rather than a dark pattern with one obvious button.
struct ConsentView: View {
    let onDecision: @MainActor (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Count my reps")
                    .font(.headline)
                    .foregroundStyle(Color.plate)

                Text("While a workout is running, ZeroLog reads how your wrist moves "
                     + "so it can count your reps and log them without you typing.")
                    .font(.footnote)

                Text("It only reads movement during a workout. Nothing is recorded "
                     + "between workouts, and your movement stays on your devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Count my reps") { onDecision(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.plate)

                Button("Not now") { onDecision(false) }
                    .buttonStyle(.bordered)

                Text("You can still log sets by hand, and change this in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// The in-session indicator guideline 2.5.14 asks for: while movement is being
/// read, it must be obvious.
struct RecordingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Text("Counting reps")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Your wrist movement is being read to count reps")
    }
}
