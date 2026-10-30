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
/// it often is not. Settings are a current-state problem, not an event stream.
///
/// Deliberately NOT @MainActor. It touches no UI, and its WCSession delegate
/// callbacks arrive off the main actor, so main-actor isolation would mean every
/// caller had to hop -- including `static let shared`, `App.init()` and
/// `AppModel`, none of which are main-actor. Isolating it there was a compile
/// error in all three places. Instead the one piece of mutable state is guarded
/// by a lock, which is what makes this safe rather than merely quiet.
final class PhoneSettingsSync: NSObject, @unchecked Sendable {

    static let shared = PhoneSettingsSync()

    private let lock = NSLock()
    /// The last thing we tried to send, held until it goes out. Not cleared on
    /// failure: the watch keeps whatever it had and honestly reports "not set
    /// up" if it had nothing, and this is retried on the next activation.
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
        lock.withLock { pending = settings }
        flush()
    }

    private func flush() {
        guard let session, session.activationState == .activated else { return }
        guard let settings = lock.withLock({ pending }) else { return }
        do {
            try session.updateApplicationContext(SettingsTransfer.payload(for: settings))
            lock.withLock { pending = nil }
        } catch {
            // Keep it pending and try again later.
        }
    }
}

extension PhoneSettingsSync: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        guard activationState == .activated else { return }
        flush()
    }

    // Required on iOS. Both fire when switching watches; reactivating keeps the
    // channel usable for the newly paired one.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // A watch that just became available may never have received settings.
        flush()
    }
}
