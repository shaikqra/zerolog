import Foundation

/// One set the watch counted, kept with the motion that produced it.
///
/// This is the piece that turns using the app into collecting data. The
/// validation set had no loaded barbell work, and recording sessions with a
/// separate app turned out not to be practical -- so instead every workout
/// exports the windows it counted, and those become the barbell data the tuner
/// never had.
///
/// Replay with `scripts/replay_sessions.py` to score real sets and re-tune the
/// per-exercise profiles against them.
public struct RecordedSet: Codable, Equatable, Sendable {
    public let reps: Int
    public let confidence: String
    /// Both estimator outputs, because a disagreement is the interesting case.
    public let peakEstimate: Int
    public let autocorrEstimate: Int
    public let sampleRateHz: Double
    public let repProfile: String?
    public let startedAt: TimeInterval
    public let seconds: Double
    /// The thinned window the count came from, so it can be re-scored offline.
    public let x: [Double]
    public let y: [Double]
    public let z: [Double]

    /// What the user said it actually was, if they corrected it. nil means they
    /// accepted the count, which is weaker evidence than an explicit
    /// correction but still useful.
    public var confirmedReps: Int?
}

/// Live numbers for the diagnostics screen.
///
/// Worth building before the first gym session rather than after. Rep counting
/// cannot be debugged from memory: "it felt wrong sometimes" is not actionable,
/// whereas "it read 8 when I did 10, peaks said 8, autocorrelation said 11, at
/// 52 Hz" points straight at the cause.
public struct CaptureDiagnostics: Equatable, Sendable {
    public var isCapturing = false
    public var samplesReceived = 0
    /// What the hardware is actually delivering, which may not be what it
    /// advertises.
    public var measuredHz: Double = 0
    public var setsDetected = 0
    /// Movement windows seen but rejected as too short or too quiet.
    public var candidatesRejected = 0
    public var lastSet: DetectedSet?
    public var droppedSamples = false

    public init() {}
}

/// Saves recorded sets so a workout can be replayed offline.
public struct DiagnosticsStore: Sendable {
    public let folderURL: URL

    public init(folderURL: URL) {
        self.folderURL = folderURL
    }

    public static func standard() throws -> DiagnosticsStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return DiagnosticsStore(folderURL: folder)
    }

    /// One file per workout, named by date so repeat sessions do not collide.
    public func fileURL(date: String, sessionType: String) -> URL {
        folderURL.appendingPathComponent("\(date)-\(sessionType).json")
    }

    @discardableResult
    public func save(_ sets: [RecordedSet], date: String, sessionType: String) throws -> URL {
        let url = fileURL(date: date, sessionType: sessionType)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(sets).write(to: url, options: .atomic)
        return url
    }

    public func load(date: String, sessionType: String) throws -> [RecordedSet] {
        let url = fileURL(date: date, sessionType: sessionType)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([RecordedSet].self, from: Data(contentsOf: url))
    }

    public func allSessions() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folderURL,
                                                      includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// Keeps the newest sessions and deletes the rest.
    ///
    /// A watch has little storage, and this data is for debugging rather than
    /// for the user, so it must never be the reason the app cannot save a
    /// workout.
    public func prune(keeping limit: Int) {
        let files = allSessions()
        guard files.count > limit else { return }
        for url in files.dropLast(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
