import XCTest
@testable import Shell

@MainActor
final class ShellTests: XCTestCase {
    func testAllSevenMonetizationModesResolveAccess() {
        for mode in [MonetizationMode.free, .ads, .adsWithRemovePurchase] {
            XCTAssertEqual(resolve(mode, entitled: false, checking: true, free: false), .allowed)
        }
        for mode in [MonetizationMode.oneTimeUnlock, .subscription] {
            XCTAssertEqual(resolve(mode, entitled: true, checking: false, free: false), .allowed)
            XCTAssertEqual(resolve(mode, entitled: false, checking: true, free: false), .checkingEntitlement)
            XCTAssertEqual(resolve(mode, entitled: false, checking: false, free: false), .purchaseRequired)
        }
        for mode in [MonetizationMode.usageCapWithOneTimeUnlock, .usageCapWithSubscription] {
            XCTAssertEqual(resolve(mode, entitled: false, checking: true, free: true), .allowed)
            XCTAssertEqual(resolve(mode, entitled: true, checking: false, free: false), .allowed)
            XCTAssertEqual(resolve(mode, entitled: false, checking: true, free: false), .checkingEntitlement)
            XCTAssertEqual(resolve(mode, entitled: false, checking: false, free: false), .usageLimitReached)
        }
    }

    func testAdVisibilityNeverLeaksBeforeRemoveAdsEntitlementCheck() {
        XCTAssertTrue(AccessController.resolveAdVisibility(mode: .ads, isEntitled: false, isChecking: true))
        XCTAssertFalse(AccessController.resolveAdVisibility(mode: .adsWithRemovePurchase, isEntitled: false, isChecking: true))
        XCTAssertTrue(AccessController.resolveAdVisibility(mode: .adsWithRemovePurchase, isEntitled: false, isChecking: false))
        XCTAssertFalse(AccessController.resolveAdVisibility(mode: .adsWithRemovePurchase, isEntitled: true, isChecking: false))
        XCTAssertFalse(AccessController.resolveAdVisibility(mode: .subscription, isEntitled: false, isChecking: false))
    }

    func testSuccessfulUsageIsPersistentAndDeduplicated() {
        let defaults = makeDefaults()
        let store = UserDefaultsUsageStore(defaults: defaults, key: "usage")
        let first = UsageLedger(limit: 2, store: store)
        XCTAssertEqual(first.recordSuccessfulAction(id: "operation-1"), .recorded(remaining: 1))
        XCTAssertEqual(first.recordSuccessfulAction(id: "operation-1"), .duplicate(remaining: 1))
        XCTAssertEqual(first.recordSuccessfulAction(id: "  "), .invalidIdentifier)
        XCTAssertEqual(first.recordSuccessfulAction(id: String(repeating: "a", count: 129)), .invalidIdentifier)
        let relaunched = UsageLedger(limit: 2, store: store)
        XCTAssertEqual(relaunched.successfulActionCount, 1)
        XCTAssertEqual(relaunched.recordSuccessfulAction(id: "operation-2"), .recorded(remaining: 0))
        XCTAssertFalse(relaunched.hasFreeActionRemaining)
        XCTAssertEqual(relaunched.recordSuccessfulAction(id: "operation-3"), .limitReached)
    }

    func testLegalAcceptanceIsVersionedAndForcesReconsent() {
        let defaults = makeDefaults()
        let first = LegalConsentStore(defaults: defaults, requiredVersion: "2026-09")
        XCTAssertTrue(first.requiresPresentation)
        XCTAssertFalse(first.isReconsent)
        first.acceptCurrentLegalVersion()
        XCTAssertFalse(first.requiresPresentation)
        XCTAssertFalse(LegalConsentStore(defaults: defaults, requiredVersion: "2026-09").requiresPresentation)
        let revised = LegalConsentStore(defaults: defaults, requiredVersion: "2026-10")
        XCTAssertTrue(revised.requiresPresentation)
        XCTAssertTrue(revised.isReconsent)
    }

    func testSubscriptionCacheExpiresButLifetimeCacheDoesNot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = EntitlementSnapshot(
            entitledProductIDs: ["lifetime", "monthly"],
            subscriptionExpiryByProductID: ["monthly": now.addingTimeInterval(60)],
            verifiedAt: now
        )
        XCTAssertTrue(snapshot.isEntitled(to: ["monthly"], at: now))
        XCTAssertFalse(snapshot.isEntitled(to: ["monthly"], at: now.addingTimeInterval(61)))
        XCTAssertTrue(snapshot.isEntitled(to: ["lifetime"], at: now.addingTimeInterval(1_000_000)))
        XCTAssertFalse(snapshot.isEntitled(to: ["unknown"], at: now))
    }

    func testProductIdentifiersAreSelectedByProfile() {
        XCTAssertEqual(configuration(.free).productIDs, [])
        XCTAssertEqual(configuration(.ads).productIDs, [])
        XCTAssertEqual(configuration(.adsWithRemovePurchase).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.oneTimeUnlock).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.subscription).productIDs, ["monthly"])
        XCTAssertEqual(configuration(.usageCapWithOneTimeUnlock).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.usageCapWithSubscription).productIDs, ["monthly"])
    }

    func testTemplateNavigationAndLanguagesAreBounded() {
        XCTAssertFalse(ShellConfiguration.destinations.isEmpty)
        XCTAssertLessThanOrEqual(ShellConfiguration.destinations.count, 5)
        XCTAssertEqual(Set(ShellConfiguration.destinations.map(\.id)).count, ShellConfiguration.destinations.count)
        XCTAssertTrue(ShellConfiguration.supportedLanguages.contains { $0.id == "system" })
        XCTAssertTrue(ShellConfiguration.supportedLanguages.contains { $0.id == "en" })
    }

    private func resolve(_ mode: MonetizationMode, entitled: Bool, checking: Bool, free: Bool) -> AccessDecision {
        AccessController.resolveDecision(mode: mode, isEntitled: entitled, isChecking: checking, hasFreeActionRemaining: free)
    }

    private func configuration(_ mode: MonetizationMode) -> MonetizationConfiguration {
        MonetizationConfiguration(mode: mode, freeSuccessfulActions: 3, lifetimeProductID: "lifetime", subscriptionProductID: "monthly")
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ShellTests.\(UUID().uuidString)")!
    }
}
