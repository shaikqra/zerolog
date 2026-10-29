import Foundation

/// What the user tells us ONCE, during onboarding.
///
/// ZeroLog's promise is zero *recurring* input, not zero input. You cannot
/// compute a credible calorie target without these, and users happily answer
/// them once. What kills tracking apps is the fifteenth time you type
/// "chicken, 180g" in a week -- that is what the app removes.
///
/// Bodyweight is the one value that keeps changing, so it is stored as a dated
/// series rather than a single number, and is meant to arrive passively from
/// HealthKit or a smart scale rather than being typed.
public struct UserProfile: Codable, Equatable, Sendable {
    public var birthYear: Int
    public var heightCm: Double
    /// Needed only by the Mifflin-St Jeor BMR equation below, which is defined
    /// in those terms. Not used for anything else.
    public var sex: BiologicalSex
    public var goal: Goal
    public var unit: WeightUnit
    /// Most recent first. Empty until the first weigh-in.
    public var bodyweightLog: [BodyweightEntry]
    /// Set only when the user overrides the computed targets.
    public var customMacroTargets: MacroTargets?

    public init(birthYear: Int, heightCm: Double, sex: BiologicalSex, goal: Goal,
                unit: WeightUnit = .kg, bodyweightLog: [BodyweightEntry] = [],
                customMacroTargets: MacroTargets? = nil) {
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.sex = sex
        self.goal = goal
        self.unit = unit
        self.bodyweightLog = bodyweightLog
        self.customMacroTargets = customMacroTargets
    }

    public var latestBodyweightKg: Double? { bodyweightLog.first?.kg }

    public func age(inYear year: Int) -> Int { max(0, year - birthYear) }
}

public enum BiologicalSex: String, Codable, Sendable { case male, female }

public enum Goal: String, Codable, Sendable {
    case loseFat, maintain, buildMuscle
}

public struct BodyweightEntry: Codable, Equatable, Sendable {
    public var date: String
    public var kg: Double

    public init(date: String, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// Daily targets. Always a range, never a single fake-exact number.
public struct MacroTargets: Codable, Equatable, Sendable {
    public var caloriesLow: Int
    public var caloriesHigh: Int
    public var proteinG: Int
    public var fatG: Int
    public var carbsG: Int

    public init(caloriesLow: Int, caloriesHigh: Int, proteinG: Int, fatG: Int, carbsG: Int) {
        self.caloriesLow = caloriesLow
        self.caloriesHigh = caloriesHigh
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
    }
}

/// Starting nutrition targets, computed by code from the profile.
///
/// IMPORTANT: this is a *seed* estimate only. Every published BMR equation is
/// a population average and will be wrong for any individual by a meaningful
/// margin. Once there is enough bodyweight-trend and intake data, the observed
/// expenditure must replace this -- the estimate is a starting point, never the
/// long-term answer. Nothing here is medical advice.
public enum Nutrition {
    /// Mifflin-St Jeor resting energy expenditure, kcal/day.
    public static func restingEnergy(profile: UserProfile, weightKg: Double, year: Int) -> Double {
        let base = 10 * weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age(inYear: year))
        return base + (profile.sex == .male ? 5 : -161)
    }

    /// Lifting 3-5x a week with an otherwise ordinary day. Deliberately a single
    /// modest factor rather than a five-option "activity level" dropdown, which
    /// users reliably over-estimate.
    public static let liftingActivityFactor = 1.5

    /// Seed daily targets. Protein is set from bodyweight (the number that
    /// actually matters for lifters), fat gets a floor for hormone health, and
    /// carbohydrate takes the remainder.
    public static func seedTargets(profile: UserProfile, weightKg: Double, year: Int) -> MacroTargets {
        let maintenance = restingEnergy(profile: profile, weightKg: weightKg, year: year)
            * liftingActivityFactor
        let adjusted: Double
        switch profile.goal {
        case .loseFat:     adjusted = maintenance * 0.80
        case .maintain:    adjusted = maintenance
        case .buildMuscle: adjusted = maintenance * 1.10
        }

        let protein = (weightKg * 2.0).rounded()              // ~2 g/kg
        let fat = max((weightKg * 0.8).rounded(), 40)         // floor, not a target
        let remaining = adjusted - protein * 4 - fat * 9
        let carbs = max((remaining / 4).rounded(), 0)

        // +/-5%: an honest band, because the inputs are estimates.
        return MacroTargets(
            caloriesLow: Int((adjusted * 0.95).rounded()),
            caloriesHigh: Int((adjusted * 1.05).rounded()),
            proteinG: Int(protein), fatG: Int(fat), carbsG: Int(carbs))
    }
}
