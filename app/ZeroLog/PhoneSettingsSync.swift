import Foundation
import WatchConnectivity
import ZeroLogCore

/// Sends the user's setup to the watch.
///
/// UNVERIFIED AT RUNTIME: WatchConnectivity needs two paired devices, so this
/// has only ever been compiled. Everything decidable lives in
/// `SettingsTransfer`, which is tested on Linux.
///
/// Why application context rather than a message: `updateApplicationContext`
/// keeps only the LATEST value and delivers it whenever the watch next becomes
/// reachable, including if it was switched off when the user finished setup.
/// Messages require the counterpart to be reachable right now, which in a gym
/// it often is not. Settings are a current-state problem, not an event stream,
/// so the context is the right tool.
@MainActor
final class PhoneSettingsSync: NSObject {

    static let shared = PhoneSettingsSync()

    /// The last thing we tried to send, so activation can retry it.
    private var pending: UserSettings?

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return .default
    }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Pushes settings to the watch. Safe to call before the session is active:
    /// the value is held and sent on activation.
    func send(_ settings: UserSettings) {
        pending = settings
        guard let session, session.activationState == .activated else { return }
        flush()
    }

    private func flush() {
        guard let session, let settings = pending else { return }
        do {
            try session.updateApplicationContext(SettingsTransfer.payload(for: settings))
            pending = nil
        } catch {
            // Deliberately silent and deliberately NOT cleared: the watch keeps
            // whatever it had and honestly reports "not set up" if it had
            // nothing. Retried on the next activation or settings change.
        }
    }
}

extension PhoneSettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            self.flush()
        }
    }

    // Required on iOS. Both fire when switching watches; reactivating keeps the
    // channel usable for the newly paired one.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // A watch that just became available may never have received settings.
        Task { @MainActor in self.flush() }
    }
}
