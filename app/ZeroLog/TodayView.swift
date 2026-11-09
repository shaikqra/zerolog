import SwiftUI
import ZeroLogCore

/// Today's workout, straight from the engine, with a button to start it.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.plan {
                    List {
                        // THE one decisive move. What today is was previously a
                        // navigation title in chrome type, while the scoreboard
                        // font -- the system's strongest device -- was spent on
                        // every exercise row equally. A screen reads flat when
                        // it opts out of its own best move for the thing that
                        // matters most, which is exactly what this did.
                        SessionHero(summary: summary(plan),
                                    upcoming: model.upcoming)
                            .listRowBackground(Color.clear)
                        // The figure: today's muscles, lit. It carries the same
                        // fact as the title ("Legs day") in a form you can read
                        // from across a gym bag, so the two are one statement,
                        // not two competing ones.
                        BodyMeshFigure(sessionType: plan.sessionType)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        // Hidden until there is something true to say; a fresh
                        // install must not greet anyone with zeros.
                        if model.progress.hasAnything {
                            Section {
                                ProgressCard(summary: model.progress, unit: plan.unit)
                            } header: {
                                SectionTitle("This week")
                            }
                            .listRowBackground(Color.surface)
                        }
                        if let problem = model.problem {
                            Section {
                                Label(problem, systemImage: "exclamationmark.triangle")
                                    .font(.ui(16))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .listRowBackground(Color.surface)
                        }
                        let changes = plan.exercises.filter { $0.change != nil }
                        if !changes.isEmpty {
                            Section {
                                ForEach(changes, id: \.exerciseId) { item in
                                    ChangeRow(item: item, unit: plan.unit) { model.undoChange(item.exerciseId) }
                                }
                            } header: {
                                SectionTitle("What I changed")
                            }
                            .listRowBackground(Color.surface)
                        }
                        Section {
                            ForEach(plan.exercises, id: \.exerciseId) { item in
                                NavigationLink {
                                    HowToView(exerciseId: item.exerciseId)
                                } label: {
                                    ExerciseRow(item: item, unit: plan.unit)
                                }
                            }
                        } header: {
                            SectionTitle("Today's plan")
                        }
                        .listRowBackground(Color.surface)
                        if !plan.skipped.isEmpty {
                            Section {
                                ForEach(plan.skipped, id: \.name) { item in
                                    Text("\(item.name): \(item.reason)")
                                        .font(.ui(15))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            } header: {
                                SectionTitle("Left out today")
                            }
                            .listRowBackground(Color.surface)
                        }
                    }
                    .darkList()
                    // The large title already renders in the scoreboard face,
                    // so it IS the focal point -- my first attempt added a hero
                    // heading underneath and produced two large headings, with
                    // the less important one ("Today") set larger. The session
                    // name belongs here; the hero carries only what supports it.
                    .navigationTitle("\(plan.sessionType.capitalized) day")
                    .safeAreaInset(edge: .bottom) {
                        Button("Start workout", action: model.start)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(20)
                            .disabled(plan.exercises.isEmpty)
                    }
                } else {
                    ContentUnavailableView(
                        "Today's workout isn't ready",
                        systemImage: "exclamationmark.triangle",
                        description: Text(model.problem ?? "Reinstall ZeroLog to fix it.")
                    )
                }
            }
            .fullScreenCover(isPresented: workoutIsOpen) {
                WorkoutView()
            }
        }
    }

    private var workoutIsOpen: Binding<Bool> {
        Binding(get: { model.active != nil }, set: { _ in })
    }

    /// "4 moves, about 38 minutes."
    private func summary(_ plan: Workout) -> String {
        let moves = plan.exercises.count == 1 ? "1 move" : "\(plan.exercises.count) moves"
        return "\(moves), about \(plan.estimatedMinutes) minutes."
    }
}

/// What supports the title: how long today is, and what follows it.
///
/// Deliberately carries NO heading of its own. The navigation large title
/// already sets the session name in the scoreboard face, and an earlier
/// version repeated it here -- two large headings, the less important one
/// bigger. One focal point per screen.
struct SessionHero: View {
    let summary: String
    let upcoming: [UpcomingSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary)
                .font(.ui(16))
                .foregroundStyle(Color.textSecondary)
            UpcomingRow(upcoming: upcoming)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseRow: View {
    let item: PlannedExercise
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.ui(18, bold: true))
                .foregroundStyle(Color.textPrimary)
            Text(prescription)
                .font(.score(26, relativeTo: .title2))
                // Red when the engine changed something, plain otherwise.
                // Every row in the accent colour meant the accent carried no
                // information -- "if every element got louder, the section got
                // flatter". Now the colour marks the rows worth looking at.
                .foregroundStyle(item.change != nil ? Color.load : Color.textPrimary)
            if let lastTime {
                // The number lifters actually want next to today's: what they
                // did last time. It was in the model all along and never shown.
                Text(lastTime)
                    .font(.ui(14))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(item.reason)
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 6)
    }

    private var lastTime: String? {
        guard let previous = item.previousWeight else { return nil }
        return "Last time: \(previous.formatted()) \(unit.rawValue)"
    }

    /// "3 × 6 at 62.5 kg", or "3 × 6, choose a weight" the first time.
    private var prescription: String {
        let sets = "\(item.sets) × \(item.targetReps)"
        guard let weight = item.weight else { return "\(sets), choose a weight" }
        return "\(sets) at \(weight.formatted()) \(unit.rawValue)"
    }
}

/// One weight change the engine made, why, and an Undo.
struct ChangeRow: View {
    let item: PlannedExercise
    let unit: WeightUnit
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ui(17, bold: true))
                .foregroundStyle(Color.textPrimary)
            Text(item.reason)
                .font(.ui(15))
                .foregroundStyle(Color.textSecondary)
            // Not a Button, deliberately: a SwiftUI List folds custom-styled
            // buttons into the row's single accessibility element, which made
            // Undo unreachable to both UI tests and VoiceOver no matter what
            // identifiers were attached. A tap gesture with an explicit
            // button trait is exposed as its own element, always.
            Text("Undo")
                .font(.ui(16, bold: true))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.lineStrong))
                .contentShape(Rectangle())
                .onTapGesture(perform: undo)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("UndoChange")
        }
        .padding(.vertical, 6)
    }

    /// "Added 5 lb to Barbell bench press" or "Lightened Barbell bench press to 120 lb".
    private var title: String {
        guard let weight = item.weight, let previous = item.previousWeight else { return item.name }
        switch item.change {
        case .increased: return "Added \((weight - previous).formatted()) \(unit.rawValue) to \(item.name)"
        case .deloaded: return "Lightened \(item.name) to \(weight.formatted()) \(unit.rawValue)"
        case nil: return item.name
        }
    }
}
