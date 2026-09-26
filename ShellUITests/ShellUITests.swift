import XCTest

final class ShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLegalOnboardingHasOneExplicitGate() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-shell.onboarding.complete", "NO",
            "-shell.legal.acceptedVersion", "",
        ]
        app.launch()

        let acceptance = app.buttons["shell.onboarding.accept"]
        let primary = app.buttons["shell.onboarding.primary"]
        XCTAssertTrue(acceptance.waitForExistence(timeout: 5))
        XCTAssertFalse(primary.isEnabled)
        acceptance.tap()
        XCTAssertTrue(primary.isEnabled)
    }

    func testSubscriptionUpgradeSkipsAppOwnedPaywallAndKeepsRestore() {
        let app = launchPastOnboarding()
        app.buttons["shell.settings"].tap()
        XCTAssertTrue(app.buttons["shell.settings.restore"].waitForExistence(timeout: 5))

        let upgrade = app.buttons["shell.settings.upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: upgrade)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        upgrade.tap()
        XCTAssertFalse(app.scrollViews["shell.paywall"].exists)
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

    /// Run this same suite through the documented destination matrix. The source
    /// remains device-agnostic; CI destinations select compact iPhone and iPad.
    func testPrimaryControlsMeetMinimumHitTarget() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-shell.onboarding.complete", "NO",
            "-shell.legal.acceptedVersion", "",
        ]
        app.launch()
        let frame = app.buttons["shell.onboarding.accept"].frame
        XCTAssertGreaterThanOrEqual(frame.height, 44)
        XCTAssertGreaterThanOrEqual(frame.width, 44)
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
