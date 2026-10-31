import XCTest
@testable import ZeroLogCore

/// Which days the user trains, and what the app may say about them.
///
/// The rule under test throughout: the app names a weekday ONLY when the user
/// told us their days. Without that it says "next", because inventing a
/// schedule is the same error as the watch inventing a gym.
final class TrainingDaysTests: XCTestCase {

    /// A fixed Monday, so these tests read the same on every day of the week.
    private var monday: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 2; c.hour = 9
        return calendar.date(from: c)!
    }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func weekday(_ d: Date?) -> Int? {
        d.map { calendar.component(.weekday, from: $0) }
    }

    func testNoAnswerMeansNoDates() {
        let dates = Engine.sessionDates(count: 3, trainingDays: [],
                                        today: monday, calendar: calendar)
        XCTAssertEqual(dates.count, 3)
        XCTAssertTrue(dates.allSatisfy { $0 == nil },
                      "An unanswered question must not produce a schedule.")
    }

    func testMondayWednesdayFridayFromMonday() {
        // 2 = Monday, 4 = Wednesday, 6 = Friday
        let dates = Engine.sessionDates(count: 3, trainingDays: [2, 4, 6],
                                        today: monday, calendar: calendar)
        XCTAssertEqual(weekday(dates[0]), 2, "Position 0 is always today.")
        XCTAssertEqual(weekday(dates[1]), 4)
        XCTAssertEqual(weekday(dates[2]), 6)
    }

    /// Opening the app on a day they do not train must still offer today.
    func testTodayIsOfferedEvenOnARestDay() {
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let dates = Engine.sessionDates(count: 2, trainingDays: [2, 4, 6],
                                        today: tuesday, calendar: calendar)
        XCTAssertEqual(weekday(dates[0]), 3, "Today is today, rest day or not.")
        XCTAssertEqual(weekday(dates[1]), 4, "The next chosen day follows it.")
    }

    func testASingleTrainingDayWrapsToNextWeek() {
        let dates = Engine.sessionDates(count: 3, trainingDays: [2],
                                        today: monday, calendar: calendar)
        XCTAssertEqual(weekday(dates[0]), 2)
        XCTAssertEqual(weekday(dates[1]), 2)
        XCTAssertEqual(weekday(dates[2]), 2)
        // Distinct weeks, not the same Monday three times.
        XCTAssertEqual(calendar.dateComponents([.day], from: dates[0]!, to: dates[1]!).day, 7)
        XCTAssertEqual(calendar.dateComponents([.day], from: dates[1]!, to: dates[2]!).day, 7)
    }

    func testEveryDaySelectedGivesConsecutiveDays() {
        let dates = Engine.sessionDates(count: 4, trainingDays: [1, 2, 3, 4, 5, 6, 7],
                                        today: monday, calendar: calendar)
        for step in 1..<4 {
            let gap = calendar.dateComponents([.day], from: dates[step - 1]!, to: dates[step]!).day
            XCTAssertEqual(gap, 1)
        }
    }

    func testUpcomingCarriesTheDatesThrough() {
        let catalog = try! Catalog.bundled()
        let sessions = Engine.upcoming(catalog: catalog, history: [], count: 3,
                                       trainingDays: [2, 4, 6],
                                       today: monday, calendar: calendar)
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(weekday(sessions[0].date), 2)
        XCTAssertEqual(weekday(sessions[1].date), 4)
        XCTAssertNotEqual(sessions[0].sessionType, sessions[1].sessionType,
                          "Consecutive sessions should still rotate.")
    }

    func testUpcomingWithoutDaysStillWorks() {
        let catalog = try! Catalog.bundled()
        let sessions = Engine.upcoming(catalog: catalog, history: [], count: 3)
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(sessions.allSatisfy { $0.date == nil })
    }

    /// Settings written before this field existed must still load, and must
    /// come back as "not asked" rather than as a guess.
    func testOldSettingsDecodeWithoutTrainingDays() throws {
        let json = """
        {"equipment":["barbell"],"minutes":45,"unit":"kg"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserSettings.self, from: json)
        XCTAssertEqual(decoded.trainingDays, [])
        XCTAssertEqual(decoded.minutes, 45)
    }

    func testTrainingDaysSurviveASaveAndLoad() throws {
        var settings = UserSettings(equipment: ["barbell"], minutes: 45, unit: .kg)
        settings.trainingDays = [2, 4, 6]
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(back.trainingDays, [2, 4, 6])
    }
}
