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
///
/// Not @MainActor, for the same reason as `PhoneSettingsSync` and `SetDetector`:
/// its delegate callbacks arrive off the main actor, and `currentSettings()` is
/// called by the planner from wherever it happens to be. Mutable state is behind
/// a lock, and the one UI-facing hop is explicit in `onChange`.
final class WatchSettingsSync: NSObject, SettingsProviding, @unchecked Sendable {

    private let store: SettingsStore?
    private let lock = NSLock()
    private var _onChange: (@Sendable () -> Void)?

    /// Called when new settings arrive, so the plan can be rebuilt immediately.
    /// The callee is responsible for hopping to the main actor.
    var onChange: (@Sendable () -> Void)? {
        get { lock.withLock { _onChange } }
        set { lock.withLock { _onChange = newValue } }
    }

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
    func currentSettings() -> UserSettings? {
        try? store?.load()
    }

    private func apply(_ context: [String: Any]) {
        guard let settings = SettingsTransfer.settings(from: context) else { return }
        try? store?.save(settings)
        onChange?()
    }
}

extension WatchSettingsSync: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        guard activationState == .activated else { return }
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
