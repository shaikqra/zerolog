import SwiftUI
import ZeroLogCore

/// The countdown between sets.
///
/// Added because the app did nothing for the 90-odd seconds between sets, which
/// is most of the time a lifter is holding their phone. An app that goes blank
/// through the majority of a workout is one you stop opening — and the plan
/// depends on it being opened four weeks running.
///
/// Counts from a stored Date rather than ticking a counter, so it stays correct
/// while the phone is locked or the app is backgrounded. A rest timer that
/// pauses when you put your phone in your pocket is wrong precisely when it is
/// being used.
struct RestTimerCard: View {
    let advice: RestAdvice
    let onSkip: () -> Void
    /// A progress ring that animates every second is exactly the kind of
    /// continuous motion Reduce Motion exists to stop. The number still
    /// updates; only the sweep does not animate.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.line, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: advice.progress)
                    .stroke(advice.isReady ? Color.done : Color.load,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.3),
                               value: advice.progress)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(advice.display)
                    .font(.score(28))
                    .foregroundStyle(advice.isReady ? Color.done : Color.textPrimary)
                    .monospacedDigit()
                // Flat wording on purpose: the product rule forbids
                // cheerleading, and a timer is the easiest place to let it in.
                Text(advice.caption)
                    .font(.ui(14))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if !advice.isReady {
                Button("Skip", action: onSkip)
                    .font(.ui(15))
                    .foregroundStyle(Color.textSecondary)
                    // Bare text is a ~20pt tap target. Apple's floor is 44.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(advice.isReady
                            ? "Rest done"
                            : "Resting, \(advice.remainingSeconds) seconds left")
    }
}

/// "Next: Pull day, then Legs day."
///
/// Deliberately the ORDER, never a date. The app has never asked which days
/// this user trains, so "Tomorrow: Pull day" would be inventing a schedule they
/// never set — the same mistake as the watch inventing a gym.
struct UpcomingRow: View {
    let upcoming: [UpcomingSession]

    var body: some View {
        if upcoming.count > 1 {
            let names = upcoming.dropFirst().map { "\($0.sessionType.capitalized) day" }
            Text("Next: \(names.joined(separator: ", then "))")
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// This week, in three numbers, with no commentary.
///
/// Hidden entirely until there is something true to say. A fresh install
/// showing "0 sets, 0 kg, 0%" is both useless and quietly discouraging, and the
/// no-shaming rule covers implication as well as wording.
struct ProgressCard: View {
    let summary: ProgressSummary
    let unit: WeightUnit

    var body: some View {
        if summary.hasAnything {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    stat("\(summary.workoutsThisWeek)",
                         summary.workoutsThisWeek == 1 ? "workout" : "workouts")
                    stat("\(summary.setsThisWeek)",
                         summary.setsThisWeek == 1 ? "set" : "sets")
                    stat(volumeText, "lifted")
                }
                if let change = summary.volumeChangePercent {
                    // Stated as a fact in both directions. A lighter week is
                    // information, not a failing — deloads are planned.
                    Text(changeText(change))
                        .font(.ui(14))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private var volumeText: String {
        let value = unit.fromKg(summary.volumeThisWeek)
        if value >= 1000 {
            return "\((value / 1000).formatted(.number.precision(.fractionLength(1))))k"
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func changeText(_ change: Double) -> String {
        let rounded = abs(change).formatted(.number.precision(.fractionLength(0)))
        if change >= 1 { return "\(rounded)% more than last week" }
        if change <= -1 { return "\(rounded)% less than last week" }
        return "About the same as last week"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.score(26))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.ui(13))
                .foregroundStyle(Color.textSecondary)
        }
    }
}
