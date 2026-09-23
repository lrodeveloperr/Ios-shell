import SwiftUI
import XCTest
@testable import Shell

@MainActor
final class ShellTests: XCTestCase {
    func testAllEightMonetizationModesResolveAccess() {
        for mode in [MonetizationMode.free, .ads, .adsWithRemovePurchase, .adsWithSubscription] {
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
        XCTAssertFalse(AccessController.resolveAdVisibility(mode: .adsWithSubscription, isEntitled: false, isChecking: true))
        XCTAssertTrue(AccessController.resolveAdVisibility(mode: .adsWithSubscription, isEntitled: false, isChecking: false))
        XCTAssertFalse(AccessController.resolveAdVisibility(mode: .adsWithSubscription, isEntitled: true, isChecking: false))
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

    func testCancelledAutoRenewalKeepsAccessUntilPaidExpiration() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expiration = now.addingTimeInterval(60)
        let condition = SubscriptionCondition.subscribed(willAutoRenew: false, expirationDate: expiration)
        XCTAssertTrue(SubscriptionAccessEvaluation.resolve(condition: condition, at: now).grantsAccess)
        XCTAssertFalse(SubscriptionAccessEvaluation.resolve(condition: condition, at: expiration).grantsAccess)
    }

    func testGracePeriodIsEntitledButBillingRetryExpiryAndRevocationAreNot() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(SubscriptionAccessEvaluation.resolve(condition: .gracePeriod(expirationDate: now.addingTimeInterval(60)), at: now).grantsAccess)
        XCTAssertFalse(SubscriptionAccessEvaluation.resolve(condition: .billingRetry, at: now).grantsAccess)
        XCTAssertFalse(SubscriptionAccessEvaluation.resolve(condition: .expired, at: now).grantsAccess)
        XCTAssertFalse(SubscriptionAccessEvaluation.resolve(condition: .revoked, at: now).grantsAccess)
    }

    func testSettingsOnlyOffersSubscriptionManagementForRelevantStoreStates() {
        XCTAssertNil(SubscriptionSettingsPresentation.resolve(.notApplicable))
        XCTAssertNil(SubscriptionSettingsPresentation.resolve(.expired))
        XCTAssertNil(SubscriptionSettingsPresentation.resolve(.revoked))

        let checking = SubscriptionSettingsPresentation.resolve(.checking)
        XCTAssertEqual(checking?.showsManagement, false)
        XCTAssertEqual(checking?.symbol, "hourglass")

        let expiration = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(
            SubscriptionSettingsPresentation.resolve(.subscribed(willAutoRenew: true, expirationDate: expiration))?.showsManagement,
            true
        )
        XCTAssertEqual(
            SubscriptionSettingsPresentation.resolve(.subscribed(willAutoRenew: false, expirationDate: expiration))?.showsManagement,
            true
        )
        XCTAssertEqual(SubscriptionSettingsPresentation.resolve(.gracePeriod(expirationDate: expiration))?.showsManagement, true)
        XCTAssertEqual(SubscriptionSettingsPresentation.resolve(.billingRetry)?.showsManagement, true)
        XCTAssertEqual(SubscriptionSettingsPresentation.resolve(.offlineCached(expirationDate: expiration))?.showsManagement, true)
    }

    func testProductIdentifiersAreSelectedByProfile() {
        XCTAssertEqual(configuration(.free).productIDs, [])
        XCTAssertEqual(configuration(.ads).productIDs, [])
        XCTAssertEqual(configuration(.adsWithRemovePurchase).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.adsWithSubscription).productIDs, ["monthly"])
        XCTAssertEqual(configuration(.oneTimeUnlock).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.subscription).productIDs, ["monthly"])
        XCTAssertEqual(configuration(.usageCapWithOneTimeUnlock).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.usageCapWithSubscription).productIDs, ["monthly"])
        XCTAssertFalse(configuration(.oneTimeUnlock).includesSubscription)
        XCTAssertTrue(configuration(.subscription).includesSubscription)
        XCTAssertTrue(configuration(.adsWithSubscription).includesSubscription)
    }

    func testTemplateNavigationAndLanguagesAreBounded() {
        XCTAssertFalse(ShellConfiguration.destinations.isEmpty)
        XCTAssertLessThanOrEqual(ShellConfiguration.destinations.count, 5)
        XCTAssertEqual(Set(ShellConfiguration.destinations.map(\.id)).count, ShellConfiguration.destinations.count)
        XCTAssertTrue(ShellConfiguration.supportedLanguages.contains { $0.id == "system" })
        XCTAssertTrue(ShellConfiguration.supportedLanguages.contains { $0.id == "en" })
    }

    func testLanguageSelectionRejectsStaleUnsupportedValues() {
        let defaults = makeDefaults()
        defaults.set("fr", forKey: "shell.language")
        let language = LanguageController(defaults: defaults, preferredLanguages: ["es-MX"])
        XCTAssertEqual(language.selection, "system")
        XCTAssertEqual(LanguageController.closestSupported(to: "es-MX"), "es")
        XCTAssertEqual(LanguageController.closestSupported(to: "fr-CA"), "en")
        XCTAssertTrue(SupportedLocaleResolver.isRightToLeft("ar-SA"))
        XCTAssertTrue(SupportedLocaleResolver.isRightToLeft("ur_PK"))
        XCTAssertFalse(SupportedLocaleResolver.isRightToLeft("en-US"))
    }

    func testSafeTemplateDefaultsAndSharedLocalizationContract() {
        XCTAssertFalse(ShellConfiguration.backup.enabled)
        XCTAssertEqual(LocalizationBaseline.localeIdentifiers.count, 31)
        XCTAssertEqual(LocalizationBaseline.sharedKeys.count, 18)
        XCTAssertEqual(ShellContract.currentVersion.split(separator: ".").count, 3)
    }

    func testLegalDestinationsUseDistinctSecureURLs() {
        let urls = [ShellConfiguration.legal.privacyURL, ShellConfiguration.legal.termsURL]
        XCTAssertEqual(Set(urls).count, urls.count)
        for url in urls {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNotNil(url.host)
        }
    }

    func testFreemiumModesAlwaysComposeTheCanvasAndLetTheProductEnforceLimits() {
        for mode in [MonetizationMode.freemiumWithOneTimeUnlock, .freemiumWithSubscription] {
            XCTAssertEqual(resolve(mode, entitled: false, checking: true, free: false), .allowed)
            XCTAssertEqual(resolve(mode, entitled: false, checking: false, free: false), .allowed)
            XCTAssertFalse(AccessController.resolveAdVisibility(mode: mode, isEntitled: false, isChecking: false))
            XCTAssertFalse(configuration(mode).includesUsageCap)
            XCTAssertFalse(configuration(mode).includesAdvertising)
        }
        XCTAssertEqual(configuration(.freemiumWithOneTimeUnlock).productIDs, ["lifetime"])
        XCTAssertEqual(configuration(.freemiumWithSubscription).productIDs, ["monthly"])
        XCTAssertTrue(configuration(.freemiumWithSubscription).includesSubscription)
    }

    func testOneTimeCacheIsRevokedByAnEmptyLocalEntitlementResult() {
        // A refund or Apple Account switch leaves currentEntitlements empty; the
        // Keychain snapshot must not keep a lifetime unlock alive.
        XCTAssertFalse(OfflineCachePolicy.mayBridge(includesSubscription: false, subscriptionStatusIsAuthoritative: false))
        // A verified "not subscribed" answer also revokes the cache.
        XCTAssertFalse(OfflineCachePolicy.mayBridge(includesSubscription: true, subscriptionStatusIsAuthoritative: true))
        // Only an unverifiable subscription status keeps a still-valid snapshot.
        XCTAssertTrue(OfflineCachePolicy.mayBridge(includesSubscription: true, subscriptionStatusIsAuthoritative: false))
    }

    func testAdditionalSubscriptionProductsKeepConfiguredOrder() {
        let multi = MonetizationConfiguration(
            mode: .subscription,
            freeSuccessfulActions: 0,
            lifetimeProductID: "lifetime",
            subscriptionProductID: "monthly",
            additionalSubscriptionProductIDs: ["yearly", "monthly"]
        )
        XCTAssertEqual(multi.orderedProductIDs, ["monthly", "yearly"])
        XCTAssertEqual(multi.productIDs, ["monthly", "yearly"])
        XCTAssertFalse(multi.offersCodeRedemption)
        XCTAssertEqual(configuration(.oneTimeUnlock).orderedProductIDs, ["lifetime"])
    }

    func testDefaultPaywallBenefitsOnlyClaimWhatTheModeGrants() {
        XCTAssertEqual(configuration(.usageCapWithSubscription).defaultPaywallBenefitKeys, ["paywall.benefit.unlimited", "paywall.benefit.support"])
        XCTAssertEqual(configuration(.adsWithRemovePurchase).defaultPaywallBenefitKeys, ["paywall.benefit.noAds", "paywall.benefit.support"])
        XCTAssertEqual(configuration(.adsWithSubscription).defaultPaywallBenefitKeys, ["paywall.benefit.noAds", "paywall.benefit.support"])
        XCTAssertFalse(configuration(.subscription).defaultPaywallBenefitKeys.contains("paywall.benefit.noAds"))
    }

    func testDailyUsageWindowResetsAtTheStartOfTheNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let clock = TestClock(Date(timeIntervalSince1970: 86_400 * 10 + 3_600))
        let store = UserDefaultsUsageStore(defaults: makeDefaults(), key: "usage")
        let ledger = UsageLedger(limit: 1, window: .day, store: store, calendar: calendar, now: { clock.date })
        XCTAssertEqual(ledger.recordSuccessfulAction(id: "a"), .recorded(remaining: 0))
        XCTAssertEqual(ledger.recordSuccessfulAction(id: "b"), .limitReached)
        clock.date = clock.date.addingTimeInterval(86_400)
        ledger.refresh()
        XCTAssertEqual(ledger.remaining, 1)
        XCTAssertEqual(ledger.recordSuccessfulAction(id: "b"), .recorded(remaining: 0))
    }

    func testVersionOneUsageRecordsStillCountTowardALifetimeLimit() {
        let defaults = makeDefaults()
        defaults.set(["legacy-1", "legacy-2"], forKey: "usage")
        let ledger = UsageLedger(limit: 3, store: UserDefaultsUsageStore(defaults: defaults, key: "usage"))
        XCTAssertEqual(ledger.successfulActionCount, 2)
        XCTAssertEqual(ledger.recordSuccessfulAction(id: "legacy-1"), .duplicate(remaining: 1))
    }

    func testUnreadableUsageStorageIsNeverOverwrittenAndRecovers() {
        let store = FlakyUsageStore()
        let ledger = UsageLedger(limit: 2, store: store)
        XCTAssertFalse(ledger.persistenceHealthy)
        XCTAssertEqual(store.saveCount, 0, "Nothing may be written while existing usage is unreadable")
        store.available = true
        ledger.refresh()
        XCTAssertTrue(ledger.persistenceHealthy)
        XCTAssertEqual(ledger.remaining, 1)
    }

    func testCompatibleShellUpgradeNeedsNoStepButMajorUpgradeDoes() throws {
        let defaults = makeDefaults()
        defaults.set("2.0.0", forKey: ShellContract.storedVersionKey)
        try ShellMigrationManager(defaults: defaults, currentVersion: "2.1.0").migrateIfNeeded(using: [])
        XCTAssertEqual(defaults.string(forKey: ShellContract.storedVersionKey), "2.1.0")

        XCTAssertThrowsError(try ShellMigrationManager(defaults: defaults, currentVersion: "3.0.0").migrateIfNeeded(using: []))
        XCTAssertEqual(defaults.string(forKey: ShellContract.storedVersionKey), "2.1.0")

        let applied = TestFlag()
        try ShellMigrationManager(defaults: defaults, currentVersion: "3.0.0").migrateIfNeeded(using: [
            ShellMigration(fromVersion: "2.1.0", toVersion: "3.0.0") { applied.value = true },
        ])
        XCTAssertTrue(applied.value)
        XCTAssertEqual(defaults.string(forKey: ShellContract.storedVersionKey), "3.0.0")
    }

    func testLocalizedLegalDocumentsFallBackToTheDefaultURL() {
        let english = URL(string: "https://example.test/privacy")!
        let spanish = URL(string: "https://example.test/es/privacidad")!
        let legal = LegalConfiguration(
            version: "1",
            privacyURL: english,
            termsURL: URL(string: "https://example.test/terms")!,
            localizedPrivacyURLs: ["es": spanish]
        )
        XCTAssertEqual(legal.privacyURL(forLanguage: "es"), spanish)
        XCTAssertEqual(legal.privacyURL(forLanguage: "fr"), english)
        XCTAssertEqual(legal.termsURL(forLanguage: "es"), legal.termsURL)
    }

    func testDestinationsAcceptSymbolOrAssetIcons() {
        XCTAssertEqual(ShellDestination(id: "a", titleKey: "a", symbol: "house").icon, .system("house"))
        XCTAssertEqual(ShellDestination(id: "b", titleKey: "b", image: "CylinderTab").icon, .asset("CylinderTab"))
    }

    func testExplicitLanguageSelectionResolvesItsOwnCatalogAndDirection() {
        let defaults = makeDefaults()
        defaults.set("es", forKey: "shell.language")
        let language = LanguageController(defaults: defaults)
        XCTAssertEqual(language.resolvedLanguageID, "es")
        XCTAssertEqual(language.layoutDirection, .leftToRight)
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

private final class TestFlag: @unchecked Sendable {
    var value = false
}

private final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

/// Storage that is unreadable (as before first unlock) until `available` is set.
private final class FlakyUsageStore: UsagePersisting, @unchecked Sendable {
    var available = false
    var saveCount = 0
    private var records = ["earlier": Date.distantPast]

    func load() -> Set<String> { Set(records.keys) }
    func save(_ actionIDs: Set<String>) throws { saveCount += 1 }

    func loadRecords() -> UsageLoadResult { available ? .loaded(records) : .unavailable }
    func saveRecords(_ records: [String: Date]) throws {
        guard available else { throw UsageStoreError.status(-25308) }
        saveCount += 1
        self.records = records
    }
}
