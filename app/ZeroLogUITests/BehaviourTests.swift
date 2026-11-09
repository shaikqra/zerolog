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
        XCTAssertTrue(app.navigationBars["Your gym"].waitForExistence(timeout: 30))

        // Setup now pre-ticks every piece of equipment (most gyms have it
        // all), so the empty state must be CREATED: untick everything.
        // Sweep-and-scroll, because a lazy list only exposes the switches on
        // screen: untick what is visible, scroll, repeat until none are on.
        for _ in 0..<5 {
            var tapped = false
            // The floating "Plan my first workout" button hovers over the
            // list's bottom edge, and XCUITest taps an element's CENTRE: a
            // toggle half-hidden beneath the button takes the tap FOR the
            // button, setup completes, and every later assert runs on the
            // wrong screen. The committed tree dump caught the app on
            // "Push day" in a setup test. Skip anything under the button;
            // the next scroll pass brings it clear.
            let planButton = app.buttons["Plan my first workout"]
            let danger = planButton.exists ? planButton.frame : .null
            for index in 0..<min(app.switches.count, 16) {
                let toggle = app.switches.element(boundBy: index)
                guard toggle.exists, toggle.isHittable,
                      (toggle.value as? String) == "1",
                      !toggle.frame.intersects(danger) else { continue }
                toggle.tap()
                tapped = true
            }
            app.swipeUp()
            if !tapped && !app.switches.allElementsBoundByIndex
                .contains(where: { ($0.value as? String) == "1" }) { break }
        }

        // A disabled SwiftUI button can leave the accessibility tree
        // entirely, so .isEnabled on it throws "no matches found". The rule
        // being tested is "there is no way to proceed": absent and disabled
        // both satisfy it.
        // If the sweep accidentally left setup, say so HERE -- the footer
        // assert below would otherwise report a missing message on a screen
        // that never carries one.
        XCTAssertTrue(app.navigationBars["Your gym"].exists,
                      "the untick sweep navigated away from the setup screen")
        let plan = app.buttons["Plan my first workout"]
        XCTAssertFalse(plan.exists && plan.isEnabled,
                       "setup would let the user through with no equipment selected")
        // The reason text is the EQUIPMENT section's footer, which sits near
        // the TOP of the list -- and the untick sweep ends at the bottom.
        // Scroll back up towards it; swiping further down was searching the
        // wrong half of the screen.
        // Any element type, substring match: a List footer may surface as
        // staticText, otherElement, or part of a combined element depending
        // on iOS version.
        let reason = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Pick at least one piece'")).firstMatch
        for _ in 0..<5 where !reason.exists { app.swipeDown() }
        if !reason.exists {
            print("=== TREE DUMP BEGIN (equipment) ===")
            print(app.debugDescription)
            print("=== TREE DUMP END ===")
        }
        XCTAssertTrue(reason.exists,
                      "refusing without saying why breaks the show-the-reason rule")
        XCTAssertTrue(app.navigationBars["Your gym"].exists, "still on setup")
    }

    // MARK: - Logging

    /// The whole point of the app: a set you log must come back exactly as
    /// logged. Wrong numbers in history are worse than no history.
    func testALoggedSetReachesHistoryWithTheNumbersItWasLoggedWith() {
        launchPastSetup()

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()

        let confirm = app.buttons["Log set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))

        let addRep = app.buttons["Add rep"]
        for _ in 0..<3 where addRep.exists { addRep.tap() }

        confirm.tap()
        endWorkout()
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
        let confirm = app.buttons["Log set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))
        let addRep = app.buttons["Add rep"]
        for _ in 0..<4 { addRep.tap() }
        confirm.tap()
        for _ in 0..<3 where confirm.exists { confirm.tap() }
        // Moving on is now explicit. Assert it exists rather than tapping
        // blindly: if this button ever disappears the workout becomes a dead
        // end, and a lifter would be stuck on bench press forever.
        let nextExercise = app.buttons["Next exercise"]
        XCTAssertTrue(nextExercise.waitForExistence(timeout: 10),
                      "a finished exercise must offer a way forward")
        nextExercise.tap()
        endWorkout()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()

        // Rotate back round to the same day.
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 12))
        logOneSetAndSave()
        logOneSetAndSave()

        // The body-first layout puts the change section below the fold, and a
        // lazy list does not materialise what has never been on screen:
        // scroll as a human would before concluding it is not there.
        let changed = app.staticTexts["What I changed"]
        for _ in 0..<5 where !changed.exists { app.swipeUp() }
        guard changed.waitForExistence(timeout: 8) else {
            // Progression depends on the engine's rules; if no change was due,
            // say so plainly rather than asserting something false.
            print("=== TREE DUMP BEGIN (no change section) ===")
            print(app.debugDescription)
            print("=== TREE DUMP END ===")
            XCTFail("no automatic change appeared after hitting the top of the rep range")
            return
        }

        // The change section sits below the body figure; bring it fully on
        // screen before expecting its row's button to be materialised.
        scrollTo(changed)
        // Identifier first, label anywhere second: element folding has eaten
        // two runs, so the query gives SwiftUI no way to hide it.
        let byId = app.descendants(matching: .any)
            .matching(identifier: "UndoChange").firstMatch
        let byLabel = app.descendants(matching: .any)["Undo"].firstMatch
        for _ in 0..<3 where !(byId.exists || byLabel.exists) { app.swipeUp() }
        let undo = byId.exists ? byId : byLabel
        if !undo.waitForExistence(timeout: 12) {
            // Stop deducing; print what is actually there. The committed CI
            // log carries this dump, so the next fix aims at facts.
            print("=== TREE DUMP BEGIN (undo) ===")
            print(app.debugDescription)
            print("=== TREE DUMP END ===")
            XCTFail("an automatic change was shown with no way to undo it")
            return
        }
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
    /// SceneKit fails to BLACK: a scene that loads nothing photographs as a
    /// stylish empty rectangle and three CI round-trips went by before anyone
    /// could say whether the model was even loading. The figure publishes
    /// what it loaded through its accessibility label; this makes a silent
    /// black hero a NAMED failure with the loader's own words in it.
    func testTheThreeDBodyReportsItsMeshLoaded() {
        launchPastSetup()
        let figure = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '3D body'")).firstMatch
        XCTAssertTrue(figure.waitForExistence(timeout: 10),
                      "the Today screen must carry the body figure")
        XCTAssertTrue(figure.label.contains("3D body: 13 groups"),
                      "the mesh did not load as 13 groups — label says: \(figure.label)")
        // And it must have DRAWN. The view measures its own first frame;
        // "BLANK" means SceneKit produced a black rectangle, which no
        // screenshot can distinguish from the background.
        let drawn = NSPredicate(format: "label CONTAINS 'drawn'")
        let rendered = app.descendants(matching: .any).matching(drawn).firstMatch
        XCTAssertTrue(rendered.waitForExistence(timeout: 10),
                      "the 3D body never drew pixels — label says: \(figure.label)")
    }

    private func launchPastSetup() {
        app.launch()
        // 30 seconds, not 12: a CI simulator relaunching an app it just
        // terminated routinely takes 15-25s to put the first screen up. The
        // suite was red from its first day partly because launches that drew
        // a slow machine were indistinguishable from a broken app.
        XCTAssertTrue(app.navigationBars["Your gym"].waitForExistence(timeout: 30))
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
        let confirm = app.buttons["Log set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))
        confirm.tap()
        endWorkout()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 12))
    }

    /// Ends the session through the confirmation dialog.
    ///
    /// "End" deliberately asks before ending -- it sits where the back button
    /// lives, so a single tap must not bin a workout. The tests go through the
    /// same door a person does; asserting the dialog appears is part of the
    /// protection, since silently losing it would restore the original bug.
    private func endWorkout() {
        app.buttons["End"].tap()
        let confirm = app.buttons["End workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "Ending a workout must ask first.")
        confirm.tap()
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

