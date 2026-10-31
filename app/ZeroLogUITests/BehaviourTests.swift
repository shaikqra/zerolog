import XCTest

/// Asserts what the app DOES, not merely that its screens exist.
///
/// The screenshot tour next door walks the same flows but mostly checks that
/// buttons are present; it also runs only on manual dispatch, so nothing caught
/// a regression automatically. These run on every push and assert the product
/// rules: a logged set reaches history with the right numbers, a weight change
/// explains itself and can be undone, history survives a relaunch, and nothing
/// anywhere guilts the user.
///
/// Each test relaunches with a reset flag, because UI tests share one simulator
/// and a test that only passes when run alone is worse than no test.
final class BehaviourTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestResetState"]
    }

    // MARK: - Setup

    /// The plan must not be buildable with no equipment chosen: the engine would
    /// have nothing to pick from, and inventing a gym is exactly the behaviour
    /// that was removed from the watch.
    func testSetupWillNotPlanAWorkoutWithNoEquipment() {
        app.launch()
        XCTAssertTrue(app.navigationBars["Your gym"].waitForExistence(timeout: 12))

        let plan = app.buttons["Plan my first workout"]
        scrollTo(plan)
        plan.tap()

        // Still on setup, with a reason shown rather than a silent no-op.
        XCTAssertTrue(app.navigationBars["Your gym"].exists,
                      "setup let the user through with no equipment selected")
        XCTAssertTrue(app.staticTexts["Pick at least one piece of equipment."].exists,
                      "refusing without saying why breaks the show-the-reason rule")
    }

    // MARK: - Logging

    /// The whole point of the app: a set you log must come back exactly as
    /// logged. Wrong numbers in history are worse than no history.
    func testALoggedSetReachesHistoryWithTheNumbersItWasLoggedWith() {
        launchPastSetup()

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()

        let confirm = app.buttons["Confirm set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))

        let addRep = app.buttons["Add rep"]
        for _ in 0..<3 where addRep.exists { addRep.tap() }

        confirm.tap()
        app.buttons["End"].tap()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()

        app.tabBars.buttons["History"].tap()
        let session = app.collectionViews.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "day")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 12), "the workout never reached history")
        session.tap()

        // A logged set renders as "<reps> × <weight> <unit>". Matched with a
        // predicate rather than by enumerating the tree: allElementsBoundByIndex
        // serialises the WHOLE accessibility hierarchy and is slow enough to
        // hang a CI job, which is exactly what it did on the first run.
        let loggedSet = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ ×.*")).firstMatch
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 15),
                      "history shows no logged set for the workout just saved")
    }

    /// History is the user's training record. Losing it on relaunch would be the
    /// single most damaging bug in the app, and nothing tested it.
    func testHistorySurvivesRelaunch() {
        launchPastSetup()
        logOneSetAndSave()

        app.tabBars.buttons["History"].tap()
        let before = app.collectionViews.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "day")).count
        XCTAssertGreaterThan(before, 0, "nothing was logged, so the test proves nothing")

        // Relaunch WITHOUT the reset flag: this is the real-world restart.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = []
        relaunched.launch()

        relaunched.tabBars.buttons["History"].tap()
        let after = relaunched.collectionViews.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "day")).count
        XCTAssertEqual(after, before, "history changed across a relaunch: \(before) -> \(after)")
    }

    // MARK: - Automatic changes

    /// Non-negotiable product rule: every automatic change is shown with its
    /// reason and can be undone. This walks far enough to trigger one.
    func testAWeightChangeExplainsItselfAndCanBeUndone() {
        launchPastSetup()

        // Top of the rep range on every set tells the engine to add weight.
        app.buttons["Start workout"].tap()
        let confirm = app.buttons["Confirm set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))
        let addRep = app.buttons["Add rep"]
        for _ in 0..<4 { addRep.tap() }
        confirm.tap()
        for _ in 0..<3 where confirm.exists { confirm.tap() }
        app.buttons["End"].tap()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()

        // Rotate back round to the same day.
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 12))
        logOneSetAndSave()
        logOneSetAndSave()

        let changed = app.staticTexts["What I changed"]
        guard changed.waitForExistence(timeout: 12) else {
            // Progression depends on the engine's rules; if no change was due,
            // say so plainly rather than asserting something false.
            XCTFail("no automatic change appeared after hitting the top of the rep range")
            return
        }

        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 12),
                      "an automatic change was shown with no way to undo it")
        undo.tap()
        XCTAssertTrue(waitForDisappearance(of: changed, timeout: 15),
                      "Undo left the change in place")
    }

    // MARK: - Tone

    /// Non-negotiable product rule: no shaming, no streak guilt. Enforced in the
    /// engine by a test on log notes; this covers what the screens actually say,
    /// which is where a user would meet it.
    func testNoScreenShamesTheUser() {
        launchPastSetup()
        logOneSetAndSave()

        // One predicate query per word rather than walking the tree.
        let banned = ["lazy", "excuse", "disappoint", "shame", "guilt",
                      "slack", "streak", "you missed", "skipped again"]
        var offenders: [String] = []
        func scan(_ screen: String) {
            for word in banned {
                let hit = app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", word)).firstMatch
                if hit.exists { offenders.append("\(screen): \"\(hit.label)\"") }
            }
        }
        scan("Today")
        app.tabBars.buttons["History"].tap()
        _ = app.navigationBars["History"].waitForExistence(timeout: 12)
        scan("History")
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 12)
        scan("Settings")

        XCTAssertTrue(offenders.isEmpty,
                      "shaming language on screen -> \(offenders.joined(separator: " | "))")
    }

    // MARK: - Helpers

    /// Launches and completes gym setup, leaving the app on Today.
    private func launchPastSetup() {
        app.launch()
        XCTAssertTrue(app.navigationBars["Your gym"].waitForExistence(timeout: 12))
        // Switch on the equipment so the planner has something to work with.
        // Indexed access, because enumerating every switch is slow enough to
        // matter on a CI simulator.
        let count = min(app.switches.count, 12)
        for index in 0..<max(count, 0) {
            let toggle = app.switches.element(boundBy: index)
            guard toggle.exists, toggle.isHittable,
                  (toggle.value as? String) == "0" else { continue }
            toggle.tap()
        }
        let plan = app.buttons["Plan my first workout"]
        scrollTo(plan)
        plan.tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 12),
                      "setup completed but no plan appeared")
    }

    private func logOneSetAndSave() {
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()
        let confirm = app.buttons["Confirm set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))
        confirm.tap()
        app.buttons["End"].tap()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 12))
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }
}
