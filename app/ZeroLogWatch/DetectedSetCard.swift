import SwiftUI
import ZeroLogCore

/// Shown when the watch logged a set by itself, or thinks it saw one.
///
/// Required by the product rule that every automatic change is shown with its
/// reason and can be undone. A set appearing in your history with no
/// explanation is the thing that makes people stop trusting the app.
///
/// Tone is deliberately flat: it states what happened. No congratulation, no
/// streaks, nothing to feel bad about.
struct DetectedSetCard: View {
    let note: String
    /// Present when the set was logged on its own and can be taken back.
    let onUndo: (@MainActor () -> Void)?
    /// Present when the watch wants one tap to accept the number.
    let onAccept: (@MainActor () -> Void)?
    let onDismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let onAccept {
                    Button("Yes", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(.plate)
                }
                if let onUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                }
                Button(onAccept == nil ? "OK" : "Change", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(10)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.plate.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}
