import SwiftUI
import ZeroLogCore

struct StartView: View {
    let plan: Workout?
    let problem: String?
    let onStart: @MainActor () -> Void
    let diagnostics: CaptureDiagnostics
    let recordedSets: Int
    let captureState: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let plan {
                    Text("\(plan.sessionType.capitalized) day")
                        .font(.title3.bold())
                    Text("\(plan.exercises.count) exercises, about \(plan.estimatedMinutes) min")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if plan != nil {
                    Button("Start workout", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .tint(.plate)
                }
                // Reachable without a debugger, because the first tester is on a
                // wrist in a gym and this is the only window into the algorithm.
                NavigationLink("Detection") {
                    DiagnosticsView(diagnostics: diagnostics,
                                    recordedSets: recordedSets,
                                    captureState: captureState)
                }
                .font(.footnote)
            }
        }
    }
}
