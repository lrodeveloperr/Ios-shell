import XCTest
@testable import Shell

@MainActor
final class ShellTests: XCTestCase {
    func testAdVisibilityTracksModeAndEntitlement() {
        let model = ShellModel()
        model.monetizationMode = .ads
        model.entitlementOverride = false
        XCTAssertTrue(model.shouldShowAd)
        model.entitlementOverride = true
        XCTAssertFalse(model.shouldShowAd)
        model.monetizationMode = .free
        model.entitlementOverride = false
        XCTAssertFalse(model.shouldShowAd)
    }

    func testShellHasNoMoreThanFiveTopLevelDestinations() {
        XCTAssertLessThanOrEqual(ShellConfiguration.destinations.count, 5)
        XCTAssertFalse(ShellConfiguration.destinations.isEmpty)
    }
}
