import Foundation
import WatchConnectivity
import ZeroLogCore

/// Receives the user's setup from the phone and caches it on the watch.
///
/// UNVERIFIED AT RUNTIME: needs two paired devices. The decoding is tested on
/// Linux via `SettingsTransfer`.
///
/// This is what finally makes the watch usable. Before it existed the watch
/// correctly reported "Open ZeroLog on your phone to set up your gym" and could
/// never progress past it, because iOS and watchOS have separate containers and
/// nothing carried the settings across.
@MainActor
final class WatchSettingsSync: NSObject, SettingsProviding {

    private let store: SettingsStore?
    /// Called when new settings arrive, so the plan can be rebuilt immediately.
    var onChange: (@MainActor () -> Void)?

    init(store: SettingsStore? = try? SettingsStore.standard()) {
        self.store = store
        super.init()
    }

    func start() {
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // The phone may have sent settings while this app was not running. The
        // context survives that, so adopt whatever is already waiting.
        apply(session.receivedApplicationContext)
    }

    /// `SettingsProviding`: reads the cache, which is the only thing the planner
    /// should ever see. nil means genuinely not set up.
    nonisolated func currentSettings() -> UserSettings? {
        try? store?.load()
    }

    private func apply(_ context: [String: Any]) {
        guard let settings = SettingsTransfer.settings(from: context) else { return }
        try? store?.save(settings)
        onChange?()
    }
}

extension WatchSettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
