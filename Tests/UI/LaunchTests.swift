import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndRelaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()

        app.launch()
        XCTAssertTrue(app.staticTexts["shell.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["shell.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
