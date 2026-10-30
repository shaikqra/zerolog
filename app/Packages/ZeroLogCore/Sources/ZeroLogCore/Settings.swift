import Foundation

/// What the user told us about their gym and how they like to train.
///
/// Lives in ZeroLogCore rather than the phone target because BOTH devices need
/// the same definition: the phone owns it, the watch receives a copy. If the two
/// sides disagreed about the wire format, the watch would silently plan the
/// wrong workout -- which is exactly the bug this type exists to prevent.
public struct UserSettings: Codable, Equatable, Sendable {
    public var equipment: Set<String>
    public var minutes: Int
    public var unit: WeightUnit

    public init(equipment: Set<String>, minutes: Int, unit: WeightUnit) {
        self.equipment = equipment
        self.minutes = minutes
        self.unit = unit
    }
}

/// Stores the user's settings on this device, as JSON next to the history file.
///
/// On the phone this is the source of truth, written at the end of setup. On the
/// watch it is a CACHE of what the phone last sent; it is empty until a sync
/// arrives, and an empty cache must make the watch say so rather than guess.
///
/// NOTE: iOS and watchOS have separate containers, so writing this file on the
/// phone does NOT make it appear on the watch. Moving it across needs
/// WatchConnectivity (`WCSession`), which only exists on-device and so cannot be
/// unit-tested here. `SettingsProviding` is the seam that transport plugs into.
public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// settings.json in the app's Application Support folder.
    public static func standard() throws -> SettingsStore {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return SettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
    }

    /// nil means "not set up yet" -- a distinct state from "set up with no
    /// equipment", and the caller must treat it differently.
    public func load() throws -> UserSettings? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(UserSettings.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ settings: UserSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}

/// Where a device gets the user's settings from.
///
/// The phone reads them from its own store; the watch reads whatever the phone
/// last sent. Both answer `nil` when setup has not happened, and NEITHER is
/// allowed to substitute a default gym -- see `PlanRequest.resolve`.
public protocol SettingsProviding: Sendable {
    func currentSettings() -> UserSettings?
}

extension SettingsStore: SettingsProviding {
    public func currentSettings() -> UserSettings? { try? load() }
}

/// Turns "settings plus history" into either a plan or an honest reason there
/// isn't one.
///
/// This exists because the watch used to fall back to a hardcoded sample gym
/// containing every machine, and plan a full workout from it. A user whose gym
/// has only dumbbells would have been shown barbell bench press, with no
/// indication the app had invented the equipment list. That breaks the product
/// rule that every automatic decision is shown with its reason, and it is worse
/// than showing nothing: a wrong plan looks exactly like a right one.
public enum PlanRequest {

    public enum Outcome: Equatable, Sendable {
        case ready(Workout)
        /// Setup has not happened on this device. Carries the words to show.
        case needsSetup(String)
    }

    public static func resolve(catalog: Catalog,
                               settings: UserSettings?,
                               history: [Session],
                               recovery: Recovery = .normal,
                               isWatch: Bool = false) -> Outcome {
        guard let settings else {
            return .needsSetup(isWatch
                ? "Open ZeroLog on your phone to set up your gym, then come back."
                : "Tell us about your gym to get your first workout.")
        }
        guard !settings.equipment.isEmpty else {
            return .needsSetup(isWatch
                ? "No equipment is set up yet. Add your gym's kit on your phone."
                : "Add at least one piece of equipment to build a workout.")
        }
        return .ready(Engine.generateWorkout(catalog: catalog,
                                             gymEquipment: settings.equipment,
                                             minutes: settings.minutes,
                                             history: history,
                                             recovery: recovery,
                                             unit: settings.unit))
    }
}
