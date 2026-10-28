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
        snap("02 Setup, bottom")
        planButton.tap()

        // 2. Today's plan.
        let startButton = app.buttons["Start workout"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        snap("03 Today")
        startButton.tap()

        // 3. Logging: first set, then the second set pre-filled from the first.
        let confirmButton = app.buttons["Confirm set"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))
        snap("04 Workout, first set")
        confirmButton.tap()
        snap("05 Workout, second set")

        // 4. End early and save.
        app.buttons["End"].tap()
        let saveButton = app.buttons["Save workout"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        snap("06 Workout done")
        saveButton.tap()

        // 5. The next plan, built from what was just logged.
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        snap("07 Today, next workout")

        // 6. History and one past workout.
        app.tabBars.buttons["History"].tap()
        let pastWorkout = app.staticTexts["Push day"]
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
