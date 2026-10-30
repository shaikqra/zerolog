import Foundation

/// The wire format for sending the user's setup from phone to watch.
///
/// Lives here rather than in either app target because both sides must agree
/// byte for byte; if they drifted, the watch would plan the wrong workout and
/// nothing would say so.
///
/// Deliberately one-directional. The phone owns settings, the watch only ever
/// receives them, so there is no conflict to resolve and no merge logic to get
/// wrong. Settings are not editable on the watch, which is also the right
/// product call: nobody wants to re-pick their gym equipment on a 40mm screen.
public enum SettingsTransfer {

    /// Key inside the WatchConnectivity application context.
    public static let contextKey = "zerolog.settings.v1"

    /// Encodes settings for `WCSession.updateApplicationContext`.
    ///
    /// JSON inside a single key rather than a dictionary of loose values:
    /// application context must be plist-compatible, and `Set<String>` is not.
    /// Encoding once here keeps the platform shim free of any conversion logic
    /// that could silently lose the equipment list.
    public static func payload(for settings: UserSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return [contextKey: data]
    }

    /// Decodes settings received on the watch.
    ///
    /// Returns nil rather than throwing for anything unexpected. A malformed
    /// context must leave the watch on its previous settings and saying "not set
    /// up", never crash and never half-apply.
    public static func settings(from context: [String: Any]) -> UserSettings? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(UserSettings.self, from: data)
    }
}

/// Whether the user has agreed to the watch reading their wrist movement.
///
/// Required by App Store guideline 2.5.14: continuous motion recording needs
/// explicit consent and a clear indication while it is happening. It is also
/// simply the right thing to ask before streaming someone's movement.
///
/// Stored as JSON rather than in UserDefaults on purpose. UserDefaults is a
/// required-reason API, so using it would mean declaring
/// NSPrivacyAccessedAPICategoryUserDefaults in both privacy manifests. A plain
/// file in Application Support avoids that for no cost.
public struct MotionConsent: Codable, Equatable, Sendable {
    /// nil means never asked, which is a different state from "asked and
    /// refused" -- the first shows the explanation, the second must not nag.
    public var granted: Bool?
    /// Which version of the explanation was agreed to. If what we capture ever
    /// materially changes, bump this and ask again rather than assuming old
    /// consent still covers it.
    public var version: Int

    public static let currentVersion = 1

    public init(granted: Bool? = nil, version: Int = MotionConsent.currentVersion) {
        self.granted = granted
        self.version = version
    }

    /// True only for a clear yes to the current explanation.
    public var allowsCapture: Bool { granted == true && version >= Self.currentVersion }

    /// True when the user has not been asked, or was asked about something
    /// narrower than what we now capture.
    public var needsAsking: Bool { granted == nil || version < Self.currentVersion }
}

public struct ConsentStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func standard() throws -> ConsentStore {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return ConsentStore(fileURL: folder.appendingPathComponent("motion-consent.json"))
    }

    /// An unreadable or missing file reads as "never asked", which is the safe
    /// default: it asks again rather than assuming permission.
    public func load() -> MotionConsent {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let consent = try? JSONDecoder().decode(MotionConsent.self, from: data)
        else { return MotionConsent() }
        return consent
    }

    public func save(_ consent: MotionConsent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(consent).write(to: fileURL, options: .atomic)
    }
}
