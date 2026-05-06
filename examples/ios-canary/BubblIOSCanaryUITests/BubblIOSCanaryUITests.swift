import XCTest

final class BubblIOSCanaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCanaryFlowPassesInAppRuntime() throws {
        let app = XCUIApplication()
        app.launch()

        let passed = app.staticTexts["canary-status-passed"]
        XCTAssertTrue(passed.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["canary-step-boot"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-track"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-cache-fallback"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-region-wake"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-failed-flush"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-sqlite-restore"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-retry-cleared"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-keychain-restore"].exists)
        XCTAssertTrue(app.staticTexts["canary-step-diagnostics"].exists)
    }
}
