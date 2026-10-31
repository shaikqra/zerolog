import Foundation

// MARK: - Rest between sets

/// What to show while the user is standing around between sets.
///
/// The app previously did nothing for the 90-odd seconds between sets, which is
/// most of the time a lifter spends holding their phone. An app that goes blank
/// during the majority of a workout is one you stop opening, and the whole plan
/// depends on it being opened four weeks running.
///
/// Rest length reuses the table the time estimator already uses, so the clock
/// agrees with the "about 38 minutes" on the plan. Two numbers that should match
/// and are computed separately will eventually disagree.
public struct RestAdvice: Equatable, Sendable {
    public let suggestedSeconds: Int
    public let elapsedSeconds: Int

    public var remainingSeconds: Int { max(0, suggestedSeconds - elapsedSeconds) }
    public var isReady: Bool { elapsedSeconds >= suggestedSeconds }
    /// 0...1, clamped, for a progress ring.
    public var progress: Double {
        guard suggestedSeconds > 0 else { return 1 }
        return min(1, max(0, Double(elapsedSeconds) / Double(suggestedSeconds)))
    }

    /// "1:30" counting down, then "Ready". Never negative, never a bare zero.
    public var display: String {
        if isReady { return "Ready" }
        let seconds = remainingSeconds
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Deliberately not encouragement. The product rule forbids cheerleading,
    /// and a timer is the easiest place to accidentally add some.
    public var caption: String {
        isReady ? "Rest done" : "Resting"
    }
}

public enum RestTimer {
    /// Falls back to the isolation figure rather than zero: an unknown movement
    /// getting "no rest needed" is worse than a slightly short suggestion.
    public static func suggestedSeconds(kind: String) -> Int {
        Engine.restSeconds[kind] ?? Engine.restSeconds["isolation"] ?? 90
    }

    public static func advice(kind: String, secondsSinceSet: Int) -> RestAdvice {
        RestAdvice(suggestedSeconds: suggestedSeconds(kind: kind),
                   elapsedSeconds: max(0, secondsSinceSet))
    }
}

extension PlannedExercise {
    /// How long to rest after a set of THIS exercise. Exposed because `kind` is
    /// internal and the UI legitimately needs the number.
    public var restSeconds: Int { RestTimer.suggestedSeconds(kind: kind) }
}

// MARK: - What is coming next

/// The next sessions in the rotation.
///
/// Deliberately ORDER, not dates. The app has never asked which days the user
/// trains, so printing "Tomorrow: Pull day" would be inventing a schedule they
/// never set -- the same class of mistake as the watch inventing a gym. Showing
/// "Next: Pull, then Legs" is true no matter when they next walk in.
public struct UpcomingSession: Equatable, Sendable {
    public let sessionType: String
    /// 0 is today's session, 1 the one after it.
    public let position: Int
}

extension Engine {
    public static func upcoming(catalog: Catalog, history: [Session],
                                count: Int = 3) -> [UpcomingSession] {
        let order = catalog.sessions["order"] ?? []
        guard !order.isEmpty, count > 0 else { return [] }
        let next = nextSessionType(catalog: catalog, history: history)
        guard let start = order.firstIndex(of: next) else { return [] }
        return (0..<count).map { step in
            UpcomingSession(sessionType: order[(start + step) % order.count], position: step)
        }
    }
}

// MARK: - Whether anything is actually improving

/// A small, honest summary for the home screen.
///
/// Every number here is computed from logged sets. Nothing is estimated and
/// nothing is encouraged; it answers "did I do more than last week" and stops.
public struct ProgressSummary: Equatable, Sendable {
    public let workoutsThisWeek: Int
    public let setsThisWeek: Int
    /// Sum of reps x weight, in kilograms, for sets logged this week.
    public let volumeThisWeek: Double
    public let volumeLastWeek: Double

    /// nil when there is nothing to compare against, which is NOT the same as
    /// zero change. A first week must not read as "0%".
    public var volumeChangePercent: Double? {
        guard volumeLastWeek > 0 else { return nil }
        return (volumeThisWeek - volumeLastWeek) / volumeLastWeek * 100
    }

    public var hasAnything: Bool { setsThisWeek > 0 || volumeLastWeek > 0 }
}

public enum Progress {

    /// Weeks run Monday to Sunday, matching how people talk about a training
    /// week. Uses a fixed ISO calendar rather than the device locale, so the
    /// same history cannot summarise differently on two phones.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func parse(_ date: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    static func volume(of session: Session) -> Double {
        session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg }
        }
    }

    public static func summary(history: [Session], today: String) -> ProgressSummary {
        guard let todayDate = parse(today),
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: todayDate)
        else {
            return ProgressSummary(workoutsThisWeek: 0, setsThisWeek: 0,
                                   volumeThisWeek: 0, volumeLastWeek: 0)
        }
        let lastWeekDay = calendar.date(byAdding: .day, value: -7, to: todayDate)
        let lastWeek = lastWeekDay.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }

        var workouts = 0, sets = 0
        var thisVolume = 0.0, lastVolume = 0.0

        for session in history {
            guard let date = parse(session.date) else { continue }
            if thisWeek.contains(date) {
                workouts += 1
                sets += session.exercises.reduce(0) { $0 + $1.sets.count }
                thisVolume += volume(of: session)
            } else if let lastWeek, lastWeek.contains(date) {
                lastVolume += volume(of: session)
            }
        }
        return ProgressSummary(workoutsThisWeek: workouts, setsThisWeek: sets,
                               volumeThisWeek: thisVolume, volumeLastWeek: lastVolume)
    }
}
