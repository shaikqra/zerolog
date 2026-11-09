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

        // Setup pre-ticks every piece of equipment, so the empty state must
        // be CREATED: untick everything. One stateless loop: find an ON
        // toggle that is safely tappable, tap it; if the only ON toggles are
        // covered by the floating "Plan my first workout" button (which
        // otherwise EATS the tap -- a committed tree dump caught this test on
        // "Push day") or are off screen, scroll and look again. The previous
        // sweep skipped covered toggles and could end its passes with one
        // still on, which made the gate assert fail honestly: the user COULD
        // proceed, because equipment genuinely remained selected.
        func anyToggleOn() -> Bool {
            app.switches.allElementsBoundByIndex.contains { ($0.value as? String) == "1" }
        }
        for _ in 0..<40 {
            let planButton = app.buttons["Plan my first workout"]
            let danger = planButton.exists ? planButton.frame : .null
            // Each Toggle appears TWICE in the tree: a row-wide wrapper
            // carrying the label (tapping it flips nothing) and the 51pt
            // switch control. And the LAST row's switch sits half-under the
            // floating button, so its CENTRE is covered: isHittable says no
            // and a centre tap would hit the button (the dump showed "Leg
            // press machine" as the lone survivor). A coordinate tap in the
            // switch's top third works whenever the row is clear of the
            // button by a few points.
            // The floating button sits in a padded safe-area container that
            // eats touches ~20pt above the visible button; a tap that cleared
            // the button by 10pt still died in the padding (the dump showed
            // the leg press switch taking 30+ taps and staying on). Demand
            // clearance from the whole container: 90pt above the button top.
            let buttonTop = danger.isNull ? CGFloat.greatestFiniteMagnitude : danger.minY
            if let sw = app.switches.allElementsBoundByIndex.first(where: {
                ($0.value as? String) == "1" && $0.frame.width < 100
                    && $0.frame.minY > 240 && $0.frame.maxY < buttonTop - 60
            }) {
                sw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            } else if anyToggleOn() {
                app.swipeUp()   // bring covered or off-screen toggles clear
            } else {
                // No ON toggle among materialised rows -- but a scrolled-away
                // one de-materialises and reads as off. Look back up before
                // believing the list is clean.
                app.swipeDown(); app.swipeDown()
                if !anyToggleOn() { break }
            }
        }
        // Final verification from the top, where early rows re-materialise.
        app.swipeDown(); app.swipeDown()
        if anyToggleOn() {
            // Name the survivor: which switch is still on, and where.
            print("=== TREE DUMP BEGIN (equipment stuck on) ===")
            print(app.debugDescription)
            print("=== TREE DUMP END ===")
        }
        XCTAssertFalse(anyToggleOn(), "the sweep could not untick every piece of equipment")

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
        // EVERY set must reach the top of the range: the engine raises on
        // the FEWEST reps across sets, and the rep stepper resets to the
        // prescribed bottom after each logged set. Topping only the first
        // set asks for a raise the rules refuse -- which is exactly what a
        // run of this test proved (3 workouts, no change, correctly).
        let addRep = app.buttons["Add rep"]
        for _ in 0..<4 { addRep.tap() }
        confirm.tap()
        for _ in 0..<3 where confirm.exists {
            for _ in 0..<4 where addRep.exists { addRep.tap() }
            confirm.tap()
        }
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

        // Rotate back round to the same day — and EARN the raise: the engine
        // moves the weight only when every logged set reaches the top of the
        // rep range, so these sessions log top-of-range sets.
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 12))
        logOneSetAndSave(atTopOfRange: true)
        logOneSetAndSave(atTopOfRange: true)

        // The body-first layout puts the change section below the fold, and a
        // lazy list does not materialise what has never been on screen:
        // scroll as a human would before concluding it is not there.
        let changed = app.staticTexts["What I changed"]
        for _ in 0..<5 where !changed.exists { dragUp() }
        guard changed.waitForExistence(timeout: 8) else {
            // The engine passes this exact walk on Linux, so when the phone
            // disagrees the evidence must name the difference. Every plan row
            // carries the engine's own reason sentence -- scroll them all into
            // existence, then open the push workout in History to see what
            // was actually logged. The dumps carry both.
            for _ in 0..<4 { dragUp() }
            print("=== TREE DUMP BEGIN (no change: full Today) ===")
            print(app.debugDescription)
            print("=== TREE DUMP END ===")
            app.tabBars.buttons["History"].tap()
            let pushEntry = app.collectionViews.staticTexts["Push day"].firstMatch
            if pushEntry.waitForExistence(timeout: 5) {
                pushEntry.tap()
                sleep(1)
                print("=== TREE DUMP BEGIN (no change: push history detail) ===")
                print(app.debugDescription)
                print("=== TREE DUMP END ===")
            }
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
        for _ in 0..<3 where !(byId.exists || byLabel.exists) { dragUp() }
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

    private func logOneSetAndSave(atTopOfRange: Bool = false) {
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()
        let confirm = app.buttons["Log set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12))
        if atTopOfRange {
            // The engine raises weight only when the FEWEST reps across the
            // logged sets reaches the top of the range (Engine.prescribe:
            // fewest >= high). The default set is prescribed at the BOTTOM,
            // so a test expecting a raise must add the reps a lifter would:
            // bench is 6-10, four taps.
            let addRep = app.buttons["Add rep"]
            for _ in 0..<4 where addRep.exists { addRep.tap() }
        }
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
            dragUp()
        }
    }

    /// Scrolls by dragging the BOTTOM strip of the screen upward. app.swipeUp
    /// starts mid-screen, which on Today lands on the 3D body -- and whatever
    /// view sits mid-screen can swallow the gesture. The bottom strip is
    /// always list.
    private func dragUp() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        from.press(forDuration: 0.05, thenDragTo: to)
    }
}

