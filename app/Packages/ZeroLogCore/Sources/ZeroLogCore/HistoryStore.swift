import Foundation

/// Saves finished sessions as a JSON file on the device, oldest first.
public struct HistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// history.json in the app's Application Support folder.
    public static func standard() throws -> HistoryStore {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return HistoryStore(fileURL: folder.appendingPathComponent("history.json"))
    }

    /// No file yet means no history. A damaged file throws, so it is never overwritten by accident.
    public func load() throws -> [Session] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([Session].self, from: Data(contentsOf: fileURL))
    }

    public func append(_ session: Session) throws {
        var sessions = try load()
        sessions.append(session)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sessions).write(to: fileURL, options: .atomic)
    }
}
