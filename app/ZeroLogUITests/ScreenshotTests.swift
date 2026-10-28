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

        // How to do an exercise, opened from the plan.
        app.staticTexts["Barbell bench press"].tap()
        XCTAssertTrue(app.navigationBars["Barbell bench press"].waitForExistence(timeout: 10))
        snap("03 How to do it")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // 3. Logging: first set, then the second set pre-filled from the first.
        let confirmButton = app.buttons["Confirm set"]
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
        let addRep = app.steppers.firstMatch.buttons["Increment"]
        for _ in 1...4 { addRep.tap() }
        confirmButton.tap()
        snap("05 Workout, second set")
        confirmButton.tap()
        confirmButton.tap()

        // 4. End early and save.
        app.buttons["End"].tap()
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

        // 7. Settings.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        snap("10 Settings")
    }

    /// Logs one set of whatever comes first and saves it, to move the rotation on.
    private func logOneSetAndSave() {
        app.buttons["Start workout"].tap()
        let confirm = app.buttons["Confirm set"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        app.buttons["End"].tap()
        let save = app.buttons["Save workout"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 10))
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
