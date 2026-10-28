import SwiftUI
import ZeroLogCore

/// Past workouts, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock",
                        description: Text("Finish a workout and it shows up here.")
                    )
                } else {
                    List {
                        ForEach(model.history.indices.reversed(), id: \.self) { index in
                            let session = model.history[index]
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(session.sessionType.capitalized) day")
                                        .font(.headline)
                                    Text("\(Today.display(session.date)), \(setsText(setCount(session)))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func setCount(_ session: Session) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let session: Session

    /// History is stored in kg; show it in the unit the user picked.
    private var unit: WeightUnit { model.settings?.unit ?? .kg }

    var body: some View {
        List {
            ForEach(session.exercises, id: \.exerciseId) { logged in
                Section(model.exerciseName(logged.exerciseId)) {
                    ForEach(Array(logged.sets.enumerated()), id: \.offset) { index, set in
                        LabeledContent("Set \(index + 1)", value: "\(set.reps) × \(unit.fromKg(set.weightKg).formatted()) \(unit.rawValue)")
                    }
                }
            }
        }
        .textCase(nil)
        .navigationTitle(Today.display(session.date))
    }
}

/// "1 set", "3 sets".
func setsText(_ count: Int) -> String {
    count == 1 ? "1 set" : "\(count) sets"
}
