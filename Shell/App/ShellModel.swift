import Observation

@MainActor
@Observable
final class ShellModel {
    var selectedDestination = ShellConfiguration.destinations.first?.id ?? ""
#if DEBUG
    var contentState = SampleContentState.populated
#endif
    var settingsPresented = false
#if DEBUG
    var labPresented = false
#endif
    var paywallPresented = false
    var manageSubscriptionsPresented = false
    private(set) var isRequestingUpgrade = false
    var startupMessage: String?

    let access: AccessController
    let ads: AdConsentService
    let language: LanguageController
    let backup: BackupCoordinator
    private let migrationManager: ShellMigrationManager

    init(
        access: AccessController = AccessController(),
        ads: AdConsentService = AdConsentService(),
        language: LanguageController = LanguageController(),
        backup: BackupCoordinator = BackupCoordinator(),
        migrationManager: ShellMigrationManager = ShellMigrationManager()
    ) {
        self.access = access
        self.ads = ads
        self.language = language
        self.backup = backup
        self.migrationManager = migrationManager
    }

    /// Reserve the correctly sized slot while consent resolves so the product
    /// canvas and native navigation do not jump when the banner arrives.
    var shouldRenderAd: Bool { access.shouldShowAd }

    func start() async {
        do { try migrationManager.migrateIfNeeded(using: ShellConfiguration.migrations) }
        catch {
            startupMessage = error.localizedDescription
            return
        }
        await access.purchases.start()
    }

    /// Subscription entry points start the StoreKit purchase directly. The
    /// app-owned paywall remains available for one-time purchases only.
    func requestUpgrade() {
        guard access.configuration.includesPurchase else { return }
        guard access.configuration.includesSubscription else {
            paywallPresented = true
            return
        }
        if case .billingRetry = access.purchases.subscriptionCondition {
            manageSubscriptionsPresented = true
            return
        }
        guard !isRequestingUpgrade, !access.purchases.isLoadingProducts else { return }
        isRequestingUpgrade = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRequestingUpgrade = false }
            if self.access.purchases.primaryProduct == nil {
                await self.access.purchases.start()
            }
            if self.access.purchases.primaryProduct != nil {
                await self.access.purchases.purchasePrimary()
            } else if !self.access.purchases.showingError {
                await self.access.purchases.purchasePrimary()
            }
        }
    }

    func prepareAdvertisingIfNeeded() async {
        await ads.prepareIfNeeded(advertisingEnabled: access.shouldShowAd)
    }
}
