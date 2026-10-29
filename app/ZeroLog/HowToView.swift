import SwiftUI
import ZeroLogCore

/// How to do one exercise: an animation slot and a few short form cues.
/// The animation is a placeholder until licensed clips exist (PLAN.md F3).
struct HowToView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: String

    var body: some View {
        let exercise = model.exercise(exerciseId)
        List {
            AnimationPlaceholder()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            Section {
                ForEach(Array((exercise?.cues ?? []).enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.score(26, relativeTo: .title2))
                            .foregroundStyle(Color.load)
                        Text(cue)
                            .font(.ui(17))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            } header: {
                SectionTitle("How to do it")
            }
            .listRowBackground(Color.surface)
        }
        .darkList()
        .navigationTitle(exercise?.name ?? "How to do it")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Stands in for the exercise animation until licensed clips are added.
private struct AnimationPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(Color.textTertiary)
            Text("Animation coming soon")
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
