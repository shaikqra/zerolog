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
/// Which weekdays you train, as seven tappable letters.
///
/// Ordered by the locale's own first weekday, so a week starts on Monday in the
/// UK and Sunday in the US without a second code path. The letters come from
/// `Calendar`, so they are translated for free.
///
/// Selecting nothing is allowed and means "not answered" -- the app then falls
/// back to describing sessions by order. It never guesses a day.
struct TrainingDaysPicker: View {
    @Binding var days: Set<Int>

    private var calendar: Calendar { .current }

    /// Weekday numbers (1...7) rotated so the locale's first day leads.
    private var ordered: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func letter(_ weekday: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols      // "M", "T", ...
        return symbols[weekday - 1]
    }

    private func name(_ weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]                // for VoiceOver
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(letter(day))
                        .font(.ui(15, bold: true))
                        .foregroundStyle(on ? Color.base : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        // Apple's 44pt floor; seven of these still fit across
                        // the narrowest supported iPhone.
                        .frame(height: 44)
                        .background(on ? Color.textPrimary : Color.surface,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name(day))
                .accessibilityValue(on ? "Training day" : "Rest day")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}

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
