import XCTest

/// Taps through the phone app like a first-time user and photographs each screen.
/// Run by .github/workflows/screenshots.yml on a fresh simulator, so it always starts at setup.
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    func testTourOfTheApp() {
        app.launch()

        // 1. First launch: gym setup.
        XCTAssertTrue(app.navigationBars["Your gym"].waitForExistence(timeout: 10))
        snap("01 Setup")
        let planButton = app.buttons["Plan my first workout"]
        scrollUntilVisible(planButton)
        planButton.tap()

        // 2. Today's plan.
        let startButton = app.buttons["Start workout"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        snap("02 Today")

        // The body as navigation: open the day tab, the camera flies to
        // today's first muscle; pick a chip, that muscle flexes and the plan
        // narrows. A screen nobody photographs is a screen nobody has checked.
        let dayTab = app.descendants(matching: .any)
            .matching(identifier: "DayTab").firstMatch
        if dayTab.waitForExistence(timeout: 5) {
            dayTab.tap()
            sleep(2)   // camera flight + flex
            snap("02b Zoomed to today's muscle")
            let chip = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'muscle-'"))
                .element(boundBy: 1)
            if chip.exists {
                chip.tap()
                sleep(2)
                snap("02c Another muscle, plan narrowed")
            }
            dayTab.tap()   // back to the whole body and the full plan
        }

        // How to do an exercise, opened from the plan.
        app.staticTexts["Barbell bench press"].tap()
        XCTAssertTrue(app.navigationBars["Barbell bench press"].waitForExistence(timeout: 10))
        snap("03 How to do it")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // 3. Logging: first set, then the second set pre-filled from the first.
        let confirmButton = app.buttons["Log set"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))
        snap("04 Workout, first set")

        // How to do it, opened mid-set.
        app.buttons["How to do it"].tap()
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        snap("04b How to do it, mid-set")
        doneButton.tap()
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))

        // Hit the top of the rep range (6 -> 10) on all 3 sets, so the next push day adds weight.
        let addRep = app.buttons["Add rep"]
        for _ in 1...4 { addRep.tap() }
        confirmButton.tap()
        snap("05 Workout, second set")
        confirmButton.tap()
        confirmButton.tap()

        // Finishing the planned sets no longer advances by itself -- that is
        // what makes a fourth set possible -- so the tour takes the same step a
        // lifter does, and photographs it.
        let nextExercise = app.buttons["Next exercise"]
        XCTAssertTrue(nextExercise.waitForExistence(timeout: 10),
                      "the workout must offer a way to move on")
        snap("05b Planned sets done")
        nextExercise.tap()

        // 4. End early and save.
        endWorkout()
        let saveButton = app.buttons["Save workout"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        snap("06 Workout done")
        saveButton.tap()

        // 5. The next plan, built from what was just logged.
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        snap("07 Today, next workout")

        // Pull and legs days, one set each, so push day comes round again.
        logOneSetAndSave()
        logOneSetAndSave()
        let undoButton = app.buttons["Undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 10))
        snap("07b What I changed")
        undoButton.tap()
        sleep(1)
        snap("07c After Undo")

        // 6. History and one past workout.
        app.tabBars.buttons["History"].tap()
        let pastWorkout = app.collectionViews.staticTexts["Push day"].firstMatch
        XCTAssertTrue(pastWorkout.waitForExistence(timeout: 10))
        snap("08 History")
        pastWorkout.tap()
        sleep(1)
        snap("09 Past workout")

        // Progress: the new tab. A screen nobody photographs is a screen
        // nobody has checked -- the lesson from the watch consent screen.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        snap("09a Progress")
        let firstLift = app.cells.firstMatch
        if firstLift.waitForExistence(timeout: 5) {
            firstLift.tap()
            snap("09b One lift over time")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // 7. Settings.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        snap("10 Settings")
        // The training-day picker sits below the fold, so the tour never
        // photographed it and it shipped unseen. Scroll to it deliberately:
        // a control nobody has looked at is a control nobody has checked.
        let dayPicker = app.buttons["Monday"].firstMatch
        scrollUntilVisible(dayPicker)
        if dayPicker.exists {
            dayPicker.tap()
            app.buttons["Wednesday"].firstMatch.tap()
            app.buttons["Friday"].firstMatch.tap()
        }
        snap("11 Training days")
    }

    /// Logs one set of whatever comes first and saves it, to move the rotation on.
    private func logOneSetAndSave() {
        app.buttons["Start workout"].tap()
        let confirm = app.buttons["Log set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        endWorkout()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 10))
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

    private func scrollUntilVisible(_ element: XCUIElement) {
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
