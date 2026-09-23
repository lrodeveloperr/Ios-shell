import Foundation
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

    /// The capabilities handed to the injected product provider.
    var featureContext: FeatureCanvasContext {
        FeatureCanvasContext(
            remainingFreeActions: { self.access.remainingFreeActions },
            recordSuccessfulAction: { self.access.recordSuccessfulAction(id: $0) },
            requestUpgrade: { self.paywallPresented = true },
            isEntitled: { self.access.isEntitled },
            accessDecision: { self.access.decision },
            resolveEntitlement: { await self.access.resolveEntitlement() },
            selectDestination: { self.selectDestination(id: $0) },
            locale: { self.language.locale }
        )
    }

    /// Returns false when the migrations did not complete.
    @discardableResult
    func start() async -> Bool {
        do { try migrationManager.migrateIfNeeded(using: ShellConfiguration.migrations) }
        catch {
            startupMessage = error.localizedDescription
            return false
        }
        await access.purchases.start()
        return true
    }

    func selectDestination(id: String) {
        guard ShellConfiguration.destinations.contains(where: { $0.id == id }) else { return }
        selectedDestination = id
    }

    func prepareAdvertisingIfNeeded() async {
        await ads.prepareIfNeeded(advertisingEnabled: access.shouldShowAd)
    }
}
