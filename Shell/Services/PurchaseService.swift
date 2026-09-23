import Observation
import StoreKit

enum EntitlementState: Equatable, Sendable {
    case checking
    case entitled(productIDs: Set<String>)
    case offlineCached(productIDs: Set<String>)
    case notEntitled
}

enum SubscriptionCondition: Equatable, Sendable {
    case notApplicable
    case checking
    case subscribed(willAutoRenew: Bool, expirationDate: Date)
    case gracePeriod(expirationDate: Date)
    case billingRetry
    case expired
    case revoked
    case offlineCached(expirationDate: Date)
}

struct SubscriptionAccessEvaluation: Equatable, Sendable {
    let grantsAccess: Bool
    let effectiveExpiration: Date?

    static func resolve(condition: SubscriptionCondition, at date: Date) -> SubscriptionAccessEvaluation {
        switch condition {
        case let .subscribed(_, expirationDate), let .gracePeriod(expirationDate), let .offlineCached(expirationDate):
            SubscriptionAccessEvaluation(grantsAccess: expirationDate > date, effectiveExpiration: expirationDate)
        case .notApplicable, .checking, .billingRetry, .expired, .revoked:
            SubscriptionAccessEvaluation(grantsAccess: false, effectiveExpiration: nil)
        }
    }
}

/// Decides whether the offline Keychain snapshot may stand in for StoreKit
/// after a refresh found no verified entitlement.
enum OfflineCachePolicy {
    /// `Transaction.currentEntitlements` is the device's authoritative local
    /// record for one-time products, so an empty result revokes the cache (for
    /// example after a refund or an Apple Account switch). Only a subscription
    /// whose status could not be verified may keep a still-valid snapshot.
    static func mayBridge(includesSubscription: Bool, subscriptionStatusIsAuthoritative: Bool) -> Bool {
        includesSubscription && !subscriptionStatusIsAuthoritative
    }
}

@MainActor
@Observable
final class PurchaseService {
    private let configuration: MonetizationConfiguration
    private let cache: any EntitlementCaching
    private let now: @Sendable () -> Date
    @ObservationIgnored
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var catalogTask: Task<Void, Never>?
    @ObservationIgnored private var storeOperationTask: Task<Void, Never>?

    private(set) var products: [Product] = []
    private(set) var entitlementState: EntitlementState = .checking
    private(set) var subscriptionCondition: SubscriptionCondition
    private(set) var isLoadingProducts = false
    /// True while a purchase or restore runs. Repeated requests join it.
    private(set) var isStoreOperationActive = false
    /// Subscription products whose introductory offer this customer may redeem.
    private(set) var introOfferEligibleProductIDs: Set<String> = []
    /// Last failure from work the customer did not start (launch catalog load,
    /// background transaction updates). It is never shown as a surprise alert.
    private(set) var lastBackgroundError: String?
    var showingError = false
    var message = ""

    init(
        configuration: MonetizationConfiguration = ShellConfiguration.monetization,
        cache: any EntitlementCaching = KeychainEntitlementCache(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.cache = cache
        self.now = now
        subscriptionCondition = configuration.includesSubscription ? .checking : .notApplicable

        if let snapshot = cache.load(), snapshot.isEntitled(to: configuration.productIDs, at: now()) {
            let cachedIDs = snapshot.entitledProductIDs.intersection(configuration.productIDs)
            entitlementState = .offlineCached(productIDs: cachedIDs)
            if configuration.includesSubscription,
               let expiration = snapshot.earliestExpiration(for: configuration.productIDs) {
                subscriptionCondition = .offlineCached(expirationDate: expiration)
                scheduleEntitlementRefresh(at: expiration)
            }
        } else if configuration.productIDs.isEmpty {
            entitlementState = .notEntitled
        }

        if configuration.includesPurchase {
            updatesTask = Task { @MainActor [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    await self.handleTransactionUpdate(result)
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        expirationTask?.cancel()
    }

    var isEntitled: Bool {
        switch entitlementState {
        case .entitled, .offlineCached: true
        case .checking, .notEntitled: false
        }
    }

    var isChecking: Bool { entitlementState == .checking }

    /// Loaded products for the selected mode, in configured display order.
    var purchasableProducts: [Product] { products }

    var primaryProduct: Product? { products.first }

    /// Loads the catalog and resolves entitlement. Concurrent calls join the
    /// active load. Pass `userInitiated` for a customer-visible retry.
    func start(userInitiated: Bool = false) async {
        guard configuration.includesPurchase else {
            entitlementState = .notEntitled
            return
        }
        if let catalogTask {
            await catalogTask.value
            return
        }
        isLoadingProducts = true
        let task = Task { @MainActor in
            await self.loadCatalog(userInitiated: userInitiated)
            await self.refreshEntitlements()
            self.isLoadingProducts = false
            self.catalogTask = nil
        }
        catalogTask = task
        await task.value
    }

    func purchasePrimary() async {
        guard let product = primaryProduct else {
            message = AppLocalization.string("purchase.productUnavailable", locale: AppLocalization.selectedLocale)
            showingError = true
            return
        }
        await purchase(product)
    }

    /// Single-flight: a repeated tap joins the active purchase or restore.
    func purchase(_ product: Product) async {
        await runStoreOperation { await self.performPurchase(product) }
    }

    /// Single-flight: a repeated tap joins the active purchase or restore.
    func restore() async {
        await runStoreOperation { await self.performRestore() }
    }

    /// Clears an alert left over from an earlier surface.
    func clearError() {
        showingError = false
    }

    /// Coalesces launch, foreground, transaction-update, purchase and expiry
    /// triggers into one serial refresh. A request that arrives mid-refresh
    /// schedules exactly one more pass.
    func refreshEntitlements() async {
        refreshRequested = true
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { @MainActor in
            while self.refreshRequested {
                self.refreshRequested = false
                await self.performEntitlementRefresh()
            }
            self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func runStoreOperation(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        if let storeOperationTask {
            await storeOperationTask.value
            return
        }
        isStoreOperationActive = true
        let task = Task { @MainActor in
            await operation()
            self.isStoreOperationActive = false
            self.storeOperationTask = nil
        }
        storeOperationTask = task
        await task.value
    }

    private func loadCatalog(userInitiated: Bool) async {
        do {
            let loaded = try await Product.products(for: configuration.productIDs)
            let order = configuration.orderedProductIDs
            products = loaded.sorted {
                (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
            }
            await updateIntroOfferEligibility()
        } catch {
            present(error, userInitiated: userInitiated)
        }
    }

    private func updateIntroOfferEligibility() async {
        var eligible = Set<String>()
        for product in products {
            guard let subscription = product.subscription, subscription.introductoryOffer != nil else { continue }
            if await subscription.isEligibleForIntroOffer { eligible.insert(product.id) }
        }
        introOfferEligibleProductIDs = eligible
    }

    private func performPurchase(_ product: Product) async {
        do {
            switch try await product.purchase() {
            case let .success(verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                await updateIntroOfferEligibility()
            case .pending:
                message = AppLocalization.string("purchase.pending", locale: AppLocalization.selectedLocale)
                showingError = true
            case .userCancelled:
                break
            @unknown default:
                // An unrecognized result must never revoke existing access.
                await refreshEntitlements()
            }
        } catch {
            present(error, userInitiated: true)
        }
    }

    private func performRestore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            present(error, userInitiated: true)
        }
    }

    private func performEntitlementRefresh() async {
        guard !configuration.productIDs.isEmpty else {
            entitlementState = .notEntitled
            return
        }

        expirationTask?.cancel()
        var productIDs = Set<String>()
        var expiries: [String: Date] = [:]
        let subscriptionResult = await loadSubscriptionStatus()

        if let subscription = subscriptionResult.evaluation,
           subscription.access.grantsAccess,
           let expiration = subscription.access.effectiveExpiration {
            productIDs.insert(subscription.productID)
            expiries[subscription.productID] = expiration
            subscriptionCondition = subscription.condition
        } else if configuration.includesSubscription, subscriptionResult.isAuthoritative {
            subscriptionCondition = subscriptionResult.evaluation?.condition ?? .expired
        }

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result),
                  configuration.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }

            if configuration.subscriptionProductIDs.contains(transaction.productID) {
                if subscriptionResult.isAuthoritative { continue }
                guard let expirationDate = transaction.expirationDate, expirationDate > now() else { continue }
                productIDs.insert(transaction.productID)
                expiries[transaction.productID] = expirationDate
                subscriptionCondition = .offlineCached(expirationDate: expirationDate)
                continue
            }

            if let expirationDate = transaction.expirationDate {
                guard expirationDate > now() else { continue }
                expiries[transaction.productID] = expirationDate
            }
            productIDs.insert(transaction.productID)
        }

        let cacheMayBridge = OfflineCachePolicy.mayBridge(
            includesSubscription: configuration.includesSubscription,
            subscriptionStatusIsAuthoritative: subscriptionResult.isAuthoritative
        )
        if productIDs.isEmpty,
           cacheMayBridge,
           let snapshot = cache.load(),
           snapshot.isEntitled(to: configuration.productIDs, at: now()) {
            let cachedIDs = snapshot.entitledProductIDs.intersection(configuration.productIDs)
            entitlementState = .offlineCached(productIDs: cachedIDs)
            if let expiration = snapshot.earliestExpiration(for: configuration.productIDs) {
                subscriptionCondition = .offlineCached(expirationDate: expiration)
                scheduleEntitlementRefresh(at: expiration)
            }
        } else if productIDs.isEmpty {
            entitlementState = .notEntitled
            if configuration.includesSubscription, subscriptionCondition == .checking {
                subscriptionCondition = .expired
            }
            try? cache.clear()
        } else {
            let snapshot = EntitlementSnapshot(
                entitledProductIDs: productIDs,
                subscriptionExpiryByProductID: expiries,
                verifiedAt: now()
            )
            do {
                try cache.save(snapshot)
                entitlementState = .entitled(productIDs: productIDs)
            } catch {
                // The verified StoreKit result remains authoritative for this process.
                entitlementState = .entitled(productIDs: productIDs)
                present(error, userInitiated: false)
            }
            scheduleEntitlementRefresh(at: expiries.values.min())
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try verified(result)
            if configuration.productIDs.contains(transaction.productID), transaction.revocationDate != nil {
                try? cache.clear()
                subscriptionCondition = .revoked
            }
            await transaction.finish()
            await refreshEntitlements()
        } catch {
            present(error, userInitiated: false)
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(value): value
        case .unverified: throw PurchaseError.failedVerification
        }
    }

    private struct VerifiedSubscriptionEvaluation {
        let productID: String
        let condition: SubscriptionCondition
        let access: SubscriptionAccessEvaluation
    }

    private struct SubscriptionStatusResult {
        let evaluation: VerifiedSubscriptionEvaluation?
        let isAuthoritative: Bool
    }

    private func loadSubscriptionStatus() async -> SubscriptionStatusResult {
        // Status is group-wide, so any loaded product of the group answers for all.
        guard configuration.includesSubscription,
              let product = products.first(where: { configuration.subscriptionProductIDs.contains($0.id) }),
              let subscription = product.subscription else {
            return SubscriptionStatusResult(evaluation: nil, isAuthoritative: false)
        }

        do {
            let statuses = try await subscription.status
            var best: VerifiedSubscriptionEvaluation?
            var verifiedRelevantStatusCount = 0
            for status in statuses {
                guard let transaction = try? verified(status.transaction),
                      let renewalInfo = try? verified(status.renewalInfo),
                      configuration.productIDs.contains(transaction.productID) else { continue }
                verifiedRelevantStatusCount += 1

                let condition: SubscriptionCondition
                if transaction.revocationDate != nil {
                    condition = .revoked
                } else {
                    switch status.state {
                    case .subscribed:
                        guard let expiration = transaction.expirationDate else { continue }
                        condition = .subscribed(willAutoRenew: renewalInfo.willAutoRenew, expirationDate: expiration)
                    case .inGracePeriod:
                        guard let expiration = renewalInfo.gracePeriodExpirationDate else { continue }
                        condition = .gracePeriod(expirationDate: expiration)
                    case .inBillingRetryPeriod:
                        condition = .billingRetry
                    case .expired:
                        condition = .expired
                    case .revoked:
                        condition = .revoked
                    default:
                        continue
                    }
                }

                let resolvedAccess = SubscriptionAccessEvaluation.resolve(condition: condition, at: now())
                let effectiveCondition: SubscriptionCondition
                if !resolvedAccess.grantsAccess {
                    switch condition {
                    case .subscribed, .gracePeriod, .offlineCached:
                        effectiveCondition = .expired
                    default:
                        effectiveCondition = condition
                    }
                } else {
                    effectiveCondition = condition
                }
                let candidate = VerifiedSubscriptionEvaluation(
                    productID: transaction.productID,
                    condition: effectiveCondition,
                    access: resolvedAccess
                )
                if best == nil || (!best!.access.grantsAccess && candidate.access.grantsAccess) ||
                    ((candidate.access.effectiveExpiration ?? .distantPast) > (best!.access.effectiveExpiration ?? .distantPast)) {
                    best = candidate
                }
            }
            // No statuses is an authoritative "not subscribed" result. Returned
            // but unverified statuses are not: keep only a still-valid local cache
            // until StoreKit can provide a verified answer.
            return SubscriptionStatusResult(
                evaluation: best,
                isAuthoritative: statuses.isEmpty || verifiedRelevantStatusCount > 0
            )
        } catch {
            return SubscriptionStatusResult(evaluation: nil, isAuthoritative: false)
        }
    }

    private func scheduleEntitlementRefresh(at expiration: Date?) {
        expirationTask?.cancel()
        guard let expiration else { return }
        let delay = max(1, expiration.timeIntervalSince(now()) + 1)
        expirationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self else { return }
            await self.refreshEntitlements()
        }
    }

    private func present(_ error: Error, userInitiated: Bool) {
        if let storeError = error as? StoreKitError, case .userCancelled = storeError { return }
        let text = error is PurchaseError
            ? AppLocalization.string("purchase.verificationFailed", locale: AppLocalization.selectedLocale)
            : error.localizedDescription
        if userInitiated {
            message = text
            showingError = true
        } else {
            lastBackgroundError = text
        }
    }
}

private enum PurchaseError: LocalizedError {
    case failedVerification
    var errorDescription: String? { nil }
}
