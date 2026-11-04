import SwiftUI
import ZeroLogCore

/// What your lifts have done over time.
///
/// The missing third of the product's own promise: "proof it worked". Until
/// now the app could tell you what to do today and what you did this week, but
/// nothing about whether you are getting stronger — which is the reason a
/// lifter opens an app on a day they are not training.
struct LiftProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                let trained = model.trainedExercises()
                if trained.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to show yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Log a few sessions and each lift will show what it has done over time, so you can see the weight going up.")
                    }
                } else {
                    List(trained, id: \.id) { exercise in
                        NavigationLink {
                            ExerciseProgressView(exerciseId: exercise.id, name: exercise.name)
                        } label: {
                            ExerciseSummaryRow(progress: model.progress(for: exercise))
                        }
                        .listRowBackground(Color.surface)
                    }
                    .darkList()
                }
            }
            .navigationTitle("Progress")
        }
    }
}

private struct ExerciseSummaryRow: View {
    let progress: ExerciseProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.name)
                .font(.ui(17, bold: true))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 8) {
                Text("\(progress.heaviest.formatted()) \(progress.unit.rawValue)")
                    .font(.score(24, relativeTo: .title3))
                    .foregroundStyle(Color.textPrimary)
                // Only shown once there are two sessions to compare. One point
                // is not a trend, and "+0" on day one implies a failure that
                // has not had the chance to happen.
                if let change = progress.changeSinceStart, change != 0 {
                    Text(change > 0 ? "+\(change.formatted())" : change.formatted())
                        .font(.ui(15, bold: true))
                        .foregroundStyle(change > 0 ? Color.done : Color.textSecondary)
                }
            }
            Text("\(progress.points.count) session\(progress.points.count == 1 ? "" : "s")")
                .font(.ui(14))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 4)
    }
}

/// One lift, session by session, with a bar per session.
///
/// A deliberately plain chart: bars scaled against the heaviest weight ever
/// lifted, newest at the bottom so the most recent is nearest the thumb. No
/// estimated one-rep max anywhere — that is a formula's opinion about a lift
/// that never happened, and this screen shows only weights actually lifted.
struct ExerciseProgressView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: String
    let name: String

    var body: some View {
        let progress = model.progress(forId: exerciseId, name: name)
        List {
            if progress.hasTrend {
                Section {
                    headline(progress)
                } header: {
                    SectionTitle("Since you started")
                }
                .listRowBackground(Color.surface)
            }
            Section {
                ForEach(Array(progress.points.enumerated().reversed()), id: \.offset) { _, point in
                    SessionBar(point: point,
                               heaviest: progress.heaviest,
                               unit: progress.unit)
                }
            } header: {
                SectionTitle("Every session")
            }
            .listRowBackground(Color.surface)
        }
        .darkList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func headline(_ progress: ExerciseProgress) -> some View {
        let change = progress.changeSinceStart ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text(change == 0 ? "Holding at \(progress.heaviest.formatted()) \(progress.unit.rawValue)"
                             : "\(change > 0 ? "+" : "")\(change.formatted()) \(progress.unit.rawValue)")
                .font(.score(44))
                .foregroundStyle(change > 0 ? Color.done : Color.textPrimary)
            // States the fact in both directions without comment. A lighter
            // stretch is information, not a failing.
            Text("Best so far \(progress.heaviest.formatted()) \(progress.unit.rawValue), across \(progress.points.count) sessions.")
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SessionBar: View {
    let point: ExerciseProgressPoint
    let heaviest: Double
    let unit: WeightUnit

    private var fraction: Double {
        guard heaviest > 0 else { return 0 }
        // Floored so a light session is still visible rather than vanishing.
        return max(0.08, point.workingWeight / heaviest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(point.workingWeight.formatted()) \(unit.rawValue)")
                    .font(.score(22, relativeTo: .body))
                    .foregroundStyle(Color.textPrimary)
                if point.isRecord {
                    Text("best")
                        .font(.ui(12, bold: true))
                        .foregroundStyle(Color.base)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.done, in: Capsule())
                }
                Spacer()
                Text(point.date)
                    .font(.ui(13))
                    .foregroundStyle(Color.textTertiary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(point.isRecord ? Color.done : Color.line)
                    .frame(width: geo.size.width * fraction, height: 6)
            }
            .frame(height: 6)
            Text("\(point.sets) set\(point.sets == 1 ? "" : "s"), best \(point.bestReps) reps")
                .font(.ui(13))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(point.date): \(point.workingWeight.formatted()) \(unit.rawValue), \(point.sets) sets, best \(point.bestReps) reps\(point.isRecord ? ", personal best" : "")")
    }
}
