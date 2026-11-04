import XCTest
@testable import ZeroLogCore

/// Backup exists to survive a reinstall, so these tests are about NOT LOSING
/// DATA rather than about file formats.
final class BackupTests: XCTestCase {

    private func session(_ date: String, _ type: String, exercises: Int) -> Session {
        let logged = (0..<exercises).map { i in
            LoggedExercise(exerciseId: "ex\(i)", sets: [LoggedSet(weightKg: 60, reps: 8)])
        }
        return Session(date: date, sessionType: type, exercises: logged)
    }

    func testRoundTripKeepsEverything() throws {
        var settings = UserSettings(equipment: ["barbell", "rack"], minutes: 45, unit: .kg)
        settings.bodyweightKg = 72
        settings.trainingDays = [2, 4, 6]
        settings.experience = .returning
        let history = [session("2026-11-01", "push", exercises: 3),
                       session("2026-11-03", "pull", exercises: 4)]

        let data = try Backup.encode(settings: settings, history: history)
        let back = try Backup.decode(data)

        XCTAssertEqual(back.settings, settings, "Settings must survive intact.")
        XCTAssertEqual(back.history, history, "Every workout must survive intact.")
        XCTAssertEqual(back.version, BackupFile.currentVersion)
    }

    func testGarbageIsRefusedNotPartiallyImported() {
        let junk = Data("not a backup at all".utf8)
        XCTAssertThrowsError(try Backup.decode(junk)) { error in
            XCTAssertEqual(error as? BackupError, .unreadable)
        }
    }

    /// A file from a FUTURE build may contain fields this one would silently
    /// drop. Refusing protects the user's record; importing would quietly
    /// truncate it and then overwrite the good copy.
    func testNewerBackupIsRefusedRatherThanTruncated() throws {
        let future = """
        {"version":99,"createdAt":"2027-01-01T00:00:00Z","history":[],"settings":null}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try Backup.decode(future)) { error in
            XCTAssertEqual(error as? BackupError, .tooNew(version: 99))
        }
    }

    func testBackupWithoutSettingsStillCarriesHistory() throws {
        let history = [session("2026-11-01", "push", exercises: 2)]
        let data = try Backup.encode(settings: nil, history: history)
        let back = try Backup.decode(data)
        XCTAssertNil(back.settings)
        XCTAssertEqual(back.history.count, 1)
    }

    // MARK: - Merge: the part that must never lose a workout

    func testRestoringDoesNotDeleteWorkoutsLoggedSinceTheBackup() {
        let backedUp = [session("2026-11-01", "push", exercises: 3)]
        let loggedSince = [session("2026-11-05", "legs", exercises: 4)]
        let merged = Backup.merge(existing: loggedSince, imported: backedUp)
        XCTAssertEqual(merged.count, 2, "Both the old and the new session must survive.")
        XCTAssertEqual(merged.map(\.date), ["2026-11-01", "2026-11-05"], "Sorted by date.")
    }

    func testTheSameSessionTwiceDoesNotDuplicate() {
        let one = [session("2026-11-01", "push", exercises: 3)]
        let merged = Backup.merge(existing: one, imported: one)
        XCTAssertEqual(merged.count, 1)
    }

    /// Restoring an older, partial copy of a session must not replace the
    /// fuller one already on the device.
    func testAPartialSessionDoesNotOverwriteACompleteOne() {
        let complete = [session("2026-11-01", "push", exercises: 5)]
        let partial = [session("2026-11-01", "push", exercises: 2)]
        let merged = Backup.merge(existing: complete, imported: partial)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].exercises.count, 5, "The fuller session wins.")
    }

    func testMergeIsOrderIndependent() {
        let a = [session("2026-11-01", "push", exercises: 5)]
        let b = [session("2026-11-01", "push", exercises: 2)]
        XCTAssertEqual(Backup.merge(existing: a, imported: b),
                       Backup.merge(existing: b, imported: a),
                       "Which side the fuller copy arrives on must not matter.")
    }

    func testEmptyDeviceRestoresEverything() {
        let backedUp = [session("2026-11-01", "push", exercises: 3),
                        session("2026-11-03", "pull", exercises: 3)]
        let merged = Backup.merge(existing: [], imported: backedUp)
        XCTAssertEqual(merged.count, 2, "The whole point: a wiped device gets it all back.")
    }

    func testSuggestedNameIsSortableAndDated() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 2
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(Backup.suggestedName(now: date), "ZeroLog-2026-11-02.json")
    }
}
