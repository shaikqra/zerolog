import SwiftUI
import ZeroLogCore

/// How long the user has been lifting.
///
/// Worded as plain descriptions rather than jargon. "Intermediate" means
/// nothing to someone who has trained for eight months and everything to
/// someone who reads training forums, so the labels describe behaviour instead.
struct ExperiencePicker: View {
    @Binding var experience: TrainingExperience

    var body: some View {
        Picker("Experience", selection: $experience) {
            ForEach(TrainingExperience.allCases, id: \.self) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        .font(.ui(16))
    }
}

/// Bodyweight, optional, in whichever unit the user lifts in.
///
/// Deliberately not required. The app has to work for someone who does not
/// want to tell it their weight, and the only cost of leaving it blank is
/// being asked to pick first-session weights by hand.
struct BodyweightField: View {
    @Binding var text: String
    let unit: WeightUnit

    var body: some View {
        HStack {
            TextField("Optional", text: $text)
                .keyboardType(.decimalPad)
                .font(.score(22))
                .foregroundStyle(Color.textPrimary)
            Text(unit.rawValue)
                .font(.ui(16))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityLabel("Bodyweight in \(unit.rawValue)")
    }
}
