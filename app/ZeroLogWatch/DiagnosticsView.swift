import SwiftUI
import ZeroLogCore

/// What the watch currently thinks is happening.
///
/// Exists because rep counting cannot be debugged from memory. "It felt wrong
/// sometimes" is not actionable; "it read 8 when I did 10, peaks said 8,
/// autocorrelation said 11, at 52 Hz" points straight at the cause. Without
/// this screen the first gym session produces impressions instead of data.
///
/// Deliberately plain and deliberately not hidden behind a debug build: the
/// founder is the first tester, on a device that cannot be attached to a
/// debugger, and this is the only window into the algorithm.
struct DiagnosticsView: View {
    let diagnostics: CaptureDiagnostics
    let recordedSets: Int
    let captureState: String

    @State private var selfTest: [SelfTest.Result] = []
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Detection")
                    .font(.headline)
                    .foregroundStyle(Color.plate)

                row("Capture", captureState)
                row("Rate", diagnostics.measuredHz > 0
                    ? "\(Int(diagnostics.measuredHz.rounded())) Hz" : "—")
                row("Samples", "\(diagnostics.samplesReceived)")
                row("Sets found", "\(diagnostics.setsDetected)")
                row("Rejected", "\(diagnostics.candidatesRejected)")
                row("Recorded", "\(recordedSets)")
                if diagnostics.droppedSamples {
                    Text("Dropped samples: a set ran longer than the buffer.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let last = diagnostics.lastSet {
                    Divider()
                    Text("Last set")
                        .font(.subheadline)
                    row("Reps", "\(last.reps)")
                    row("Confidence", last.confidence.rawValue)
                    row("Length", "\(Int(last.seconds.rounded()))s")
                    row("Profile", last.repProfile ?? "generic")
                } else {
                    Text("No set counted yet this session.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // The engine has never executed on Apple hardware. arm64
                // floating point, a different Swift runtime and a different
                // Foundation all sit between the tested code and this watch, so
                // this runs the same traces the Linux tests run and says whether
                // the answers match. A failure here means a platform difference,
                // which is worth knowing in ten seconds rather than after a
                // confusing session in a gym.
                //
                // It proves the pipeline computes what it computed on Linux. It
                // proves nothing about whether a real bench press looks like
                // what the tuner expects.
                Button(running ? "Running…" : "Run self-test") {
                    running = true
                    // Off the main actor: six traces is a few hundred thousand
                    // samples and would visibly stall the screen.
                    Task.detached {
                        let results = SelfTest.run()
                        await MainActor.run {
                            selfTest = results
                            running = false
                        }
                    }
                }
                .font(.footnote)
                .disabled(running)

                if !selfTest.isEmpty {
                    Text(SelfTest.summary(selfTest))
                        .font(.caption.bold())
                        // BOTH branches must name Color explicitly. A bare
                        // `.orange` against a `Color` makes the compiler infer
                        // HierarchicalShapeStyle for the ternary and then reject
                        // the mismatch -- which is what broke the watch build.
                        .foregroundStyle(selfTest.allSatisfy(\.passed) ? Color.plate : Color.orange)
                    ForEach(selfTest, id: \.name) { result in
                        HStack(alignment: .top, spacing: 4) {
                            Text(result.passed ? "ok" : "FAIL")
                                .font(.caption2.bold())
                                .foregroundStyle(result.passed ? Color.secondary : Color.orange)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(result.name).font(.caption2)
                                Text(result.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}
