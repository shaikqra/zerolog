import Foundation

/// One exercise from the database (Resources/exercises.json).
public struct Exercise: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let pattern: String
    public let kind: String
    public let equipment: [String]
    public let repRange: [Int]
    public let incrementKg: Double
    public let sets: Int
    public let detectable: Bool
}

/// A kind of gym equipment the user can say their gym has.
public struct EquipmentType: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
}

/// The exercise database plus the push/pull/legs session layouts.
public struct Catalog: Decodable, Sendable {
    /// In display order. Kept as a list (not a dictionary) because snake_case key conversion would rename ids.
    public let equipmentTypes: [EquipmentType]
    public let exercises: [Exercise]
    public let sessions: [String: [String]]

    /// Loads the database that ships inside the app.
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Catalog.self, from: Data(contentsOf: url))
    }
}

public enum Recovery: String, Codable, Sendable {
    case normal, low
}

// MARK: - History (what the user actually did)

public struct LoggedSet: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

public struct LoggedExercise: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: [LoggedSet]

    public init(exerciseId: String, sets: [LoggedSet]) {
        self.exerciseId = exerciseId
        self.sets = sets
    }
}

public struct Session: Codable, Equatable, Sendable {
    public var date: String
    public var sessionType: String
    public var exercises: [LoggedExercise]

    public init(date: String, sessionType: String, exercises: [LoggedExercise]) {
        self.date = date
        self.sessionType = sessionType
        self.exercises = exercises
    }
}

// MARK: - Output (today's workout)

public struct PlannedExercise: Equatable, Sendable {
    public let exerciseId: String
    public let name: String
    public let detectable: Bool
    public internal(set) var sets: Int
    /// nil means first time: the user picks a starting weight.
    public let weightKg: Double?
    public let targetReps: Int
    public let reason: String
    /// Weight step for this exercise (e.g. 2.5 kg for a barbell), used by the weight picker.
    public let incrementKg: Double
    let kind: String
}

public struct SkippedItem: Equatable, Sendable {
    public let name: String
    public let reason: String
}

public struct Workout: Equatable, Sendable {
    public let sessionType: String
    public let estimatedMinutes: Int
    public let exercises: [PlannedExercise]
    public let skipped: [SkippedItem]
}
