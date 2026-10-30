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
    public let incrementLb: Double
    public let sets: Int
    public let detectable: Bool
    /// Names the tuned calibration in `RepCounter.profiles`. nil = use the generic
    /// profile. ALWAYS pass this to the counter: per-exercise calibration is the
    /// only defence against the estimators agreeing on a wrong number.
    public let repProfile: String?
    /// True ONLY when this exact movement was in the MM-Fit validation set. False
    /// means the profile is borrowed from a similar movement and is an untested
    /// transfer -- do not quote accuracy figures for these.
    public let repProfileVerified: Bool?
    /// Short form tips shown on the "How to do it" screen.
    public let cues: [String]

    public var hasVerifiedRepProfile: Bool { repProfileVerified ?? false }

    /// Smallest weight jump for this exercise in the given unit.
    public func increment(in unit: WeightUnit) -> Double {
        unit == .kg ? incrementKg : incrementLb
    }
}

/// The unit the user lifts in. History is always stored in kg; plans come out in this unit.
public enum WeightUnit: String, Codable, Sendable {
    case kg, lb

    static let kgPerLb = 0.45359237

    /// kg -> this unit, to 2 decimals so a set logged as 135 lb comes back as exactly 135.
    public func fromKg(_ kg: Double) -> Double {
        self == .kg ? kg : (kg / Self.kgPerLb * 100).rounded(.toNearestOrEven) / 100
    }

    /// This unit -> kg, for saving to history.
    public func toKg(_ weight: Double) -> Double {
        self == .kg ? weight : weight * Self.kgPerLb
    }
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

/// A weight change the engine made from last time. The app shows it with its reason and an Undo.
public enum WeightChange: String, Sendable {
    case increased, deloaded
}

public struct PlannedExercise: Equatable, Sendable {
    public let exerciseId: String
    public let name: String
    public let detectable: Bool
    /// Passed straight to `RepCounter.count(exercise:)` when logging this exercise.
    public let repProfile: String?
    public internal(set) var sets: Int
    /// In the workout's unit. nil means first time: the user picks a starting weight.
    public let weight: Double?
    public let targetReps: Int
    public let reason: String
    /// Weight step for this exercise in the workout's unit (e.g. 2.5 kg or 5 lb for a barbell).
    public let increment: Double
    /// Working weight last time, in the workout's unit. nil the first time.
    public let previousWeight: Double?
    /// Set when the engine changed the weight from last time. nil when it held or it's the first time.
    public let change: WeightChange?
    let kind: String
    let repRange: [Int]
}

public struct SkippedItem: Equatable, Sendable {
    public let name: String
    public let reason: String
}

public struct Workout: Equatable, Sendable {
    public let sessionType: String
    public let unit: WeightUnit
    public let estimatedMinutes: Int
    public let exercises: [PlannedExercise]
    public let skipped: [SkippedItem]
}
