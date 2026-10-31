import SwiftUI
import ZeroLogCore

/// Logging a workout on the phone: one set at a time, pre-filled, confirm with one tap.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var weight = 20.0
    @State private var reps = 8
    @State private var showingHowTo = false
    /// Ticks once a second purely to redraw the countdown. The time itself
    /// comes from a stored Date, so a missed tick cannot drift the clock.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var restDismissed = false
    @State private var confirmingEnd = false

    /// Starting weight when there's no history: an empty barbell (20 kg or 45 lb).
    private func startingWeight(_ unit: WeightUnit) -> Double {
        unit == .lb ? 45 : 20
    }

    var body: some View {
        NavigationStack {
            if let active = model.active {
                if let item = active.current {
                    setScreen(active: active, item: item)
                } else {
                    summary(active)
                }
            }
        }
    }

    private func setScreen(active: ActiveWorkout, item: PlannedExercise) -> some View {
        let unit = active.plan.unit
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProgressSegments(count: active.plan.exercises.count, current: active.exerciseIndex)
                if !restDismissed, let advice = model.restAdvice(now: now), !advice.isReady {
                    RestTimerCard(advice: advice) { restDismissed = true }
                }
                VStack(alignment: .leading, spacing: 8) {
                    // Was .score(44), the same weight as the numbers below, so
                    // the screen had two peaks. Mid-set the exercise name is
                    // the one thing you already know -- it is context, and the
                    // weight and reps are the decision. Still large enough to
                    // read from a bench at arm's length.
                    Text(item.name)
                        .font(.score(30))
                        .foregroundStyle(Color.textPrimary)
                    SetDots(total: item.sets, current: active.setNumber)
                }
                HStack(alignment: .top, spacing: 20) {
                    BigNumber(value: weight.formatted(), unit: unit.rawValue,
                              hint: "Steps of \(item.increment.formatted()) \(unit.rawValue)",
                              lessLabel: "Remove weight", moreLabel: "Add weight",
                              less: { weight = max(0, weight - item.increment) },
                              more: { weight = min(1000, weight + item.increment) })
                    BigNumber(value: "\(reps)", unit: "reps", hint: "Aim for \(item.targetReps)",
                              lessLabel: "Remove rep", moreLabel: "Add rep",
                              less: { reps = max(1, reps - 1) },
                              more: { reps = min(50, reps + 1) })
                }
                Text(item.reason)
                    .font(.ui(16))
                    .foregroundStyle(Color.textPrimary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
                Button {
                    showingHowTo = true
                } label: {
                    Label("How to do it", systemImage: "play.fill")
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .padding(20)
        }
        .background(Color.base)
        .navigationTitle("\(active.plan.sessionType.capitalized) day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Sits exactly where the back button lives, so a misplaced tap
                // used to end the session outright. It asks now. The wording
                // states what actually happens -- endEarly() goes to the
                // summary and keeps logged sets -- because a confirmation that
                // implies losing work is its own kind of lie.
                Button("End") { confirmingEnd = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Skip exercise", action: model.skipExercise)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.confirm(weight: weight, reps: reps)
                // A new set restarts the rest, so an earlier dismissal must not
                // suppress the next countdown.
                restDismissed = false
                now = Date()
            } label: {
                Label("Log set", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(20)
            .background(Color.base)
        }
        .confirmationDialog("End this workout?", isPresented: $confirmingEnd,
                            titleVisibility: .visible) {
            Button("End workout", role: .destructive, action: model.endEarly)
            Button("Keep going", role: .cancel) { }
        } message: {
            Text("Sets you have already logged are kept.")
        }
        .onReceive(tick) { now = $0 }
        // A sheet, not a push: pushing would re-run the refill below and undo the user's changes.
        .sheet(isPresented: $showingHowTo) {
            NavigationStack {
                HowToView(exerciseId: item.exerciseId)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingHowTo = false }
                        }
                    }
            }
        }
        // Refill reps and weight whenever a new set starts.
        .task(id: "\(active.exerciseIndex)-\(active.setNumber)") {
            weight = active.suggestedWeight ?? startingWeight(unit)
            reps = active.suggestedReps
        }
    }

    private func summary(_ active: ActiveWorkout) -> some View {
        let count = active.totalSetsLogged
        return VStack(spacing: 16) {
            Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 72))
                .foregroundStyle(count > 0 ? Color.done : Color.textTertiary)
            Text(count > 0 ? "Workout done" : "Nothing logged")
                .font(.score(48))
                .foregroundStyle(Color.textPrimary)
            if count > 0 {
                Text("\(setsText(count)) logged. Your next plan builds on \(count == 1 ? "it" : "them").")
                    .font(.ui(17))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.base)
        .safeAreaInset(edge: .bottom) {
            Button(count > 0 ? "Save workout" : "Close", action: model.finish)
                .buttonStyle(PrimaryButtonStyle())
                .padding(20)
        }
    }
}

/// One bar per exercise: green for done, red for the current one, grey for what's left.
/// One dot per set: done, doing, still to do.
///
/// Replaces the line "Set 1 of 3", which stated the same fact without showing
/// it. The dots are the only place green appears during a working set, which
/// is what makes finishing one feel like something happened.
///
/// Not numbered markers -- sets genuinely ARE a sequence, so the shape earns
/// its place rather than decorating.
private struct SetDots: View {
    let total: Int
    /// 1-based: the set being worked on right now.
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Circle()
                    .strokeBorder(index == current ? Color.textPrimary : .clear, lineWidth: 2)
                    .background(Circle().fill(fill(index)))
                    .frame(width: 12, height: 12)
            }
            Text("Set \(current) of \(total)")
                .font(.ui(16))
                .foregroundStyle(Color.textSecondary)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set \(current) of \(total), \(current - 1) done")
    }

    private func fill(_ index: Int) -> Color {
        if index < current { return .done }        // finished
        if index == current { return .clear }      // in progress: outline only
        return .line                               // still to come
    }
}

private struct ProgressSegments: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Color.done : index == current ? Color.load : Color.line)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Exercise \(current + 1) of \(count)")
    }
}

/// A giant number with its unit, round minus and plus buttons, and a hint underneath.
/// Shared with the edit-set sheet, so a correction uses the same control as
/// the original entry. Two different steppers for the same job would drift.
struct BigNumber: View {
    let value: String
    let unit: String
    let hint: String
    let lessLabel: String
    let moreLabel: String
    let less: () -> Void
    let more: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.score(88))
                    .foregroundStyle(Color.textPrimary)
                Text(unit)
                    .font(.ui(18))
                    .foregroundStyle(Color.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            HStack(spacing: 12) {
                RoundButton(systemImage: "minus", label: lessLabel, action: less)
                RoundButton(systemImage: "plus", label: moreLabel, action: more)
            }
            Text(hint)
                .font(.ui(14))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 56, height: 56)
                .background(Color.raised, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
