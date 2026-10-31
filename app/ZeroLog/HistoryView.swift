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
                                SessionDetailView(sessionIndex: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(session.sessionType.capitalized) day")
                                        .font(.ui(18, bold: true))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("\(Today.display(session.date)), \(setsText(setCount(session)))")
                                        .font(.ui(15))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listRowBackground(Color.surface)
                    }
                    .darkList()
                }
            }
            .navigationTitle("History")
        }
    }

    private func setCount(_ session: Session) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }
}

/// One past workout, with every set editable.
///
/// Addressed by INDEX rather than by holding a copy of the session: an edit
/// rewrites history, and a view holding a stale copy would keep showing the
/// old numbers and then write them back over the correction.
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionIndex: Int

    @State private var editing: SetAddress?
    @State private var pendingDelete: SetAddress?

    private var unit: WeightUnit { model.settings?.unit ?? .kg }
    private var session: Session? {
        model.history.indices.contains(sessionIndex) ? model.history[sessionIndex] : nil
    }

    var body: some View {
        Group {
            if let session {
                List {
                    ForEach(Array(session.exercises.enumerated()), id: \.offset) { exerciseIndex, logged in
                        Section {
                            ForEach(Array(logged.sets.enumerated()), id: \.offset) { setIndex, set in
                                let address = SetAddress(session: sessionIndex,
                                                         exercise: exerciseIndex, set: setIndex)
                                Button {
                                    editing = address
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("Set \(setIndex + 1)")
                                            .font(.ui(17))
                                            .foregroundStyle(Color.textSecondary)
                                        Spacer()
                                        Text("\(set.reps) × \(unit.fromKg(set.weightKg).formatted()) \(unit.rawValue)")
                                            .font(.score(26, relativeTo: .title2))
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        pendingDelete = address
                                    }
                                }
                            }
                        } header: {
                            SectionTitle(model.exerciseName(logged.exerciseId))
                        }
                        .listRowBackground(Color.surface)
                    }
                    Text("Tap a set to change it, or swipe left to delete it.")
                        .font(.ui(14))
                        .foregroundStyle(Color.textSecondary)
                        .listRowBackground(Color.clear)
                }
                .darkList()
                .navigationTitle(Today.display(session.date))
            } else {
                // The whole workout was deleted from underneath this screen.
                ContentUnavailableView("Workout deleted", systemImage: "trash")
            }
        }
        .sheet(item: $editing) { address in
            EditSetSheet(address: address, unit: unit)
        }
        // A confirmation, because deleting a set can silently take the whole
        // workout with it when it is the last one.
        .confirmationDialog(model.describeDelete(at: pendingDelete ?? SetAddress(session: -1, exercise: 0, set: 0)) ?? "Delete this set?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { model.deleteSet(at: pendingDelete) }
                pendingDelete = nil
            }
            Button("Keep it", role: .cancel) { pendingDelete = nil }
        }
    }
}

extension SetAddress: Identifiable {
    public var id: String { "\(session)-\(exercise)-\(set)" }
}

/// Correcting one set. Pre-filled with what is there now, so a small fix is a
/// small change rather than a re-entry.
struct EditSetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let address: SetAddress
    let unit: WeightUnit

    @State private var weight = 0.0
    @State private var reps = 0
    @State private var loaded = false

    /// Plate-sized steps, so an edit lands on a weight that can be loaded.
    private var step: Double { unit == .kg ? 2.5 : 5 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 20) {
                    BigNumber(value: weight.formatted(), unit: unit.rawValue,
                              hint: "Steps of \(step.formatted()) \(unit.rawValue)",
                              lessLabel: "Remove weight", moreLabel: "Add weight",
                              less: { weight = max(0, weight - step) },
                              more: { weight += step })
                    BigNumber(value: "\(reps)", unit: reps == 1 ? "rep" : "reps",
                              hint: " ",
                              lessLabel: "Remove rep", moreLabel: "Add rep",
                              less: { reps = max(1, reps - 1) },
                              more: { reps += 1 })
                }
                Text("Changing a past set also changes what the app plans next, "
                     + "because your next weight comes from what you actually lifted.")
                    .font(.ui(14))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding(24)
            .background(Color.base)
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.editSet(at: address, weightKg: unit.toKg(weight), reps: reps)
                        dismiss()
                    }
                    .disabled(reps < 1)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing = HistoryEdit.read(model.history, at: address) {
                    weight = unit.fromKg(existing.weightKg)
                    reps = existing.reps
                }
            }
        }
    }
}

/// "1 set", "3 sets".
func setsText(_ count: Int) -> String {
    count == 1 ? "1 set" : "\(count) sets"
}
