import Foundation

/// "What do I actually put on the bar?"
///
/// Every lifter does this arithmetic in their head between sets and some of
/// them get it wrong. The app already knows the target weight, so it can just
/// say it. Pure code, no AI, deterministic -- the house rule.
public enum PlateMath {

    /// Plates a normal commercial gym has, heaviest first, per unit.
    public static func standardPlates(_ unit: WeightUnit) -> [Double] {
        unit == .kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5]
    }

    /// Olympic bar weight.
    public static func standardBar(_ unit: WeightUnit) -> Double {
        unit == .kg ? 20 : 45
    }

    public struct Loading: Equatable, Sendable {
        /// Plates for ONE side, heaviest first.
        public let perSide: [Double]
        /// What the bar actually weighs once loaded. May differ from the target.
        public let achievedWeight: Double
        public let barWeight: Double
        /// True when the target could not be made exactly from available plates.
        public var isApproximate: Bool { achievedWeight != requestedWeight }
        let requestedWeight: Double

        /// "2 x 10 + 1 x 2.5 per side" -- sentence case, no bullets, per the design rules.
        public func describe(unit: WeightUnit) -> String {
            guard !perSide.isEmpty else { return "Empty bar" }
            var counts: [(plate: Double, n: Int)] = []
            for plate in perSide {
                if let last = counts.last, last.plate == plate {
                    counts[counts.count - 1].n += 1
                } else {
                    counts.append((plate, 1))
                }
            }
            let parts = counts.map { "\($0.n) x \(trim($0.plate))" }
            return parts.joined(separator: " + ") + " per side"
        }

        private func trim(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
    }

    /// Greedy plate selection. Greedy is provably optimal for these
    /// denominations because each plate divides evenly into the larger ones.
    ///
    /// Returns nil when the target is lighter than the bar -- the caller should
    /// show a dumbbell or machine instead of pretending.
    public static func load(target: Double, unit: WeightUnit,
                            bar: Double? = nil, plates: [Double]? = nil) -> Loading? {
        let barWeight = bar ?? standardBar(unit)
        let available = (plates ?? standardPlates(unit)).sorted(by: >)
        guard target >= barWeight else { return nil }

        var remainingPerSide = (target - barWeight) / 2
        var chosen: [Double] = []
        for plate in available {
            while remainingPerSide >= plate - 0.0001 {
                chosen.append(plate)
                remainingPerSide -= plate
            }
        }
        let achieved = barWeight + chosen.reduce(0, +) * 2
        return Loading(perSide: chosen, achievedWeight: round2(achieved),
                       barWeight: barWeight, requestedWeight: round2(target))
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrEven) / 100
    }
}
