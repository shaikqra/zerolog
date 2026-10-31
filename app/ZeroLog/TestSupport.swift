import Foundation

/// Test-only state reset, so UI tests start from a known point.
///
/// UI tests run one after another against the SAME simulator, so without this
/// each test inherits whatever the previous one left behind -- the first-launch
/// setup screen only appears once, and any test that needs it would pass alone
/// and fail in a suite. That class of flakiness is worse than no test at all,
/// because it trains you to ignore red.
///
/// Compiled out of release builds entirely. A flag that erases the user's
/// training history must not exist in a shipped binary, no matter how it is
/// guarded at runtime.
enum TestSupport {

    static let resetArgument = "-uiTestResetState"

    static func resetStateIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains(resetArgument) else { return }
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                        in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
        else { return }
        // Named explicitly rather than clearing the directory: other things live
        // in Application Support, and a blanket delete is the kind of
        // convenience that eventually removes something it should not.
        for name in ["settings.json", "history.json", "in-progress.json",
                     "motion-consent.json", "sessions"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        #endif
    }
}
