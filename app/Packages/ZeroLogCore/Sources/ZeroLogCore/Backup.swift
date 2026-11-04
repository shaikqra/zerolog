import Foundation

/// Everything the user has created, in one file they can keep.
///
/// This exists because of a hard practical fact, not as a feature wish: an app
/// signed with a free Apple ID expires after SEVEN DAYS, and re-signing it
/// usually takes the app's data with it. Without a way to carry history across
/// a reinstall, a week of real logged workouts -- the only honest test of
/// whether this app survives daily use -- is destroyed by the signing process
/// rather than by anything the app did.
///
/// The format is deliberately plain JSON with a version number. It is the
/// user's own training record; they should be able to read it, keep it, and
/// move it somewhere else without asking permission.
public struct BackupFile: Codable, Equatable, Sendable {
    /// Bumped only when the shape changes in a way an older build cannot read.
    public static let currentVersion = 1

    public var version: Int
    /// When the backup was taken, for the user's benefit when they have several.
    public var createdAt: String
    public var settings: UserSettings?
    public var history: [Session]

    public init(version: Int = BackupFile.currentVersion,
                createdAt: String,
                settings: UserSettings?,
                history: [Session]) {
        self.version = version
        self.createdAt = createdAt
        self.settings = settings
        self.history = history
    }
}

public enum BackupError: Error, Equatable {
    /// The file is not a ZeroLog backup, or is damaged.
    case unreadable
    /// Written by a newer build than this one.
    case tooNew(version: Int)
}

public enum Backup {
    /// Pretty-printed with sorted keys so a person can actually read it, and so
    /// two backups of the same data compare equal in a diff.
    public static func encode(settings: UserSettings?, history: [Session],
                              now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = ISO8601DateFormatter().string(from: now)
        return try encoder.encode(BackupFile(createdAt: stamp,
                                             settings: settings,
                                             history: history))
    }

    /// Refuses rather than guesses.
    ///
    /// A backup that silently imports half a file, or quietly drops workouts it
    /// does not understand, is worse than one that fails loudly -- the user
    /// would believe their record was safe when it was not.
    public static func decode(_ data: Data) throws -> BackupFile {
        guard let file = try? JSONDecoder().decode(BackupFile.self, from: data) else {
            throw BackupError.unreadable
        }
        guard file.version <= BackupFile.currentVersion else {
            throw BackupError.tooNew(version: file.version)
        }
        return file
    }

    /// A filename a person can sort by eye: ZeroLog-2026-11-02.json
    public static func suggestedName(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "ZeroLog-\(f.string(from: now)).json"
    }

    /// Merges an imported history into what is already on the device.
    ///
    /// Restoring onto a device that has since logged new workouts must not
    /// delete them, so this unions the two by (date, sessionType) and keeps the
    /// version with MORE logged exercises when both exist -- a partial session
    /// should never overwrite a complete one. Result is sorted by date so the
    /// history screen reads correctly afterwards.
    public static func merge(existing: [Session], imported: [Session]) -> [Session] {
        var byKey: [String: Session] = [:]
        for session in existing + imported {
            let key = "\(session.date)|\(session.sessionType)"
            if let current = byKey[key] {
                if session.exercises.count > current.exercises.count {
                    byKey[key] = session
                }
            } else {
                byKey[key] = session
            }
        }
        return byKey.values.sorted { $0.date < $1.date }
    }
}
