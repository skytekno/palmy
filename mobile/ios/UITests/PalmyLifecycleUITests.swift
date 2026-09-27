import XCTest

@MainActor final class PalmyLifecycleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func prepareAccount(in app: XCUIApplication) {
        app.launch()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Synthetic lifecycle\n")
        let prepare = app.buttons["onboarding.prepare"]
        reveal(prepare, in: app)
        prepare.tap()
        XCTAssertTrue(app.buttons["onboarding.create"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testIdleRecoveryAcknowledgementSurvivesBackground() {
        let app = XCUIApplication()
        prepareAccount(in: app)
        let create = app.buttons["onboarding.create"]
        XCTAssertFalse(create.isEnabled)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(app.staticTexts["dashboard.greeting"].exists)
        app.terminate()
    }

    func testSignedInBackgroundReturnsToLockedOnboarding() throws {
        guard ProcessInfo.processInfo.environment["PALMY_UI_LIVE_API"] == "1" else {
            throw XCTSkip("Set PALMY_UI_LIVE_API=1 and run a disposable API at 127.0.0.1:8100 for the real signed-in lifecycle test.")
        }
        let app = XCUIApplication()
        prepareAccount(in: app)
        let acknowledgement = app.switches["onboarding.recoveryAcknowledged"]
        reveal(acknowledgement, in: app)
        // SwiftUI exposes the labeled row as a switch; target the trailing control itself.
        acknowledgement.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let create = app.buttons["onboarding.create"]
        reveal(create, in: app)
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: create)
        waitForExpectations(timeout: 5)
        create.tap()
        XCTAssertTrue(app.staticTexts["dashboard.greeting"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.textFields["onboarding.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["dashboard.greeting"].exists)
        XCTAssertFalse(app.buttons["onboarding.create"].exists)
        app.terminate()
    }
}
