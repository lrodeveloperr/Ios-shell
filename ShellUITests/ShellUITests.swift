import XCTest

final class ShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsFourRealWorkAreas() {
        let app = XCUIApplication()
        app.launch()
        let tabs = app.tabBars.firstMatch.buttons
        XCTAssertEqual(tabs.count, 4)
        for title in ["Jobs", "Run", "Setups", "Records"] {
            XCTAssertTrue(tabs[title].exists)
        }
        XCTAssertTrue(app.buttons["Start repeat job"].exists)
    }

    func testPaywallExposesPurchaseAndRestoreControls() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-shell.onboarding.complete", "YES",
            "-shell.legal.acceptedVersion", "1",
        ]
        app.launch()

        app.buttons["shell.settings"].tap()
        app.buttons["shell.settings.upgrade"].tap()
        XCTAssertTrue(app.scrollViews["shell.paywall"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shell.paywall.restore"].exists)
    }

    func testSettingsOpensWithoutTerminatingApp() {
        let app = launchPastOnboarding()
        let settings = app.buttons["shell.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testEveryTabHasVisibleIcon() {
        let app = launchPastOnboarding()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let tabs = tabBar.buttons.allElementsBoundByIndex
        XCTAssertFalse(tabs.isEmpty)
        for tab in tabs {
            XCTAssertGreaterThan(tab.descendants(matching: .image).count, 0, "Missing icon for tab: \(tab.label)")
        }
    }

    func testStartJobIsReachableAndTouchSized() {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Start repeat job"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        start.tap()
        XCTAssertTrue(app.navigationBars["Start repeat job"].waitForExistence(timeout: 5))
    }

    private func launchPastOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-shell.onboarding.complete", "YES",
            "-shell.legal.acceptedVersion", "1",
        ]
        app.launch()
        return app
    }
}
