import SwiftUI
import ZeroLogCore

/// Today's workout, straight from the engine, with a button to start it.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// The muscle the camera is parked on, nil = whole body. The founder's
    /// spec, verbatim: press the day, zoom to the body part being trained;
    /// pick triceps, the triceps flex. The body IS the navigation.
    @State private var focusedMuscle: String? = nil
    @State private var muscleMode = false

    private static let catalog = try? Catalog.bundled()

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
                        // The body comes FIRST and takes the screen: it is not
                        // an illustration above a list, it is the way in. The
                        // founder asked for exactly this order -- open the app,
                        // see the body, the day sits below it.
                        BodyMeshFigure(sessionType: plan.sessionType,
                                       focus: focusedMuscle)
                            .frame(maxWidth: .infinity)
                            .frame(height: muscleMode ? 300 : 380)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .animation(.easeInOut(duration: 0.4), value: muscleMode)
                        // The day tab. Tapping it opens the body up: the camera
                        // flies to today's first muscle and a chip per muscle
                        // appears -- pick one and that muscle flexes while the
                        // plan below narrows to its exercises.
                        DayTab(summary: summary(plan),
                               upcoming: model.upcoming,
                               isOpen: muscleMode) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                muscleMode.toggle()
                                focusedMuscle = muscleMode ? todayGroups(plan).first : nil
                            }
                        }
                        .listRowBackground(Color.surface)
                        .listRowSeparator(.hidden)
                        if muscleMode {
                            MuscleChips(groups: todayGroups(plan),
                                        selected: focusedMuscle) { group in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    focusedMuscle = (focusedMuscle == group) ? nil : group
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
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
                            ForEach(visibleExercises(plan), id: \.exerciseId) { item in
                                NavigationLink {
                                    HowToView(exerciseId: item.exerciseId)
                                } label: {
                                    ExerciseRow(item: item, unit: plan.unit)
                                }
                            }
                        } header: {
                            SectionTitle(planHeader)
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

    /// Today's muscles, in plan order, deduplicated — one chip each.
    private func todayGroups(_ plan: Workout) -> [String] {
        var seen = Set<String>(), ordered: [String] = []
        for item in plan.exercises {
            guard let pattern = Self.catalog?.exercise(id: item.exerciseId)?.pattern else { continue }
            for g in MuscleMap.groups(for: pattern) where seen.insert(g).inserted {
                ordered.append(g)
            }
        }
        return ordered
    }

    /// The plan, narrowed to the focused muscle when there is one.
    private func visibleExercises(_ plan: Workout) -> [PlannedExercise] {
        guard let focusedMuscle else { return plan.exercises }
        return plan.exercises.filter { item in
            guard let pattern = Self.catalog?.exercise(id: item.exerciseId)?.pattern else { return true }
            return MuscleMap.groups(for: pattern).contains(focusedMuscle)
        }
    }

    private var planHeader: String {
        guard let focusedMuscle else { return "Today's plan" }
        return "\(MuscleMap.spoken(focusedMuscle)) exercises"
    }

    /// "4 moves, about 38 minutes."
    private func summary(_ plan: Workout) -> String {
        let moves = plan.exercises.count == 1 ? "1 move" : "\(plan.exercises.count) moves"
        return "\(moves), about \(plan.estimatedMinutes) minutes."
    }
}

/// The day tab under the body: what today is, how long, what follows —
/// and the way into the muscles. Carries no heading of its own; the
/// navigation large title owns the session name (one focal point).
struct DayTab: View {
    let summary: String
    let upcoming: [UpcomingSession]
    let isOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary)
                        .font(.ui(16))
                        .foregroundStyle(Color.textSecondary)
                    UpcomingRow(upcoming: upcoming)
                        .padding(.top, 2)
                }
                Spacer(minLength: 12)
                HStack(spacing: 5) {
                    Text(isOpen ? "Close" : "Muscles")
                        .font(.ui(14, bold: true))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.textPrimary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary) \(isOpen ? "Close the muscle view" : "Show today's muscles")")
        .accessibilityIdentifier("DayTab")
    }
}

/// One chip per muscle today trains. Tapping a chip flies the camera to it
/// and the muscle flexes; tapping again returns to the whole body.
struct MuscleChips: View {
    let groups: [String]
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.self) { group in
                    let isOn = group == selected
                    Text(MuscleMap.spoken(group))
                        .font(.ui(15, bold: true))
                        .foregroundStyle(isOn ? Color.black : Color.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(isOn ? Color.white : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(isOn ? Color.clear : Color.lineStrong))
                        .contentShape(Capsule())
                        .onTapGesture { pick(group) }
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("muscle-\(group)")
                }
            }
            .padding(.vertical, 2)
        }
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
