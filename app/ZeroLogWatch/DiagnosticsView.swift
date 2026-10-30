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
