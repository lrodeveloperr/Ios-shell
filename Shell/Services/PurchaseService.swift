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

    private(set) var products: [Product] = []
    private(set) var entitlementState: EntitlementState = .checking
    private(set) var subscriptionCondition: SubscriptionCondition
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
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

    var primaryProduct: Product? {
        let desiredID: String
        switch configuration.mode {
        case .adsWithRemovePurchase, .oneTimeUnlock, .usageCapWithOneTimeUnlock:
            desiredID = configuration.lifetimeProductID
        case .adsWithSubscription, .subscription, .usageCapWithSubscription, .freemiumSubscription:
            desiredID = configuration.subscriptionProductID
        case .free, .ads:
            return nil
        }
        return products.first { $0.id == desiredID }
    }

    var subscriptionProducts: [Product] {
        let ids = configuration.subscriptionProductIDs
        return products.filter { ids.contains($0.id) }.sorted {
            $0.id == configuration.subscriptionProductID ||
                ($1.id != configuration.subscriptionProductID && $0.id < $1.id)
        }
    }

    func start() async {
        guard !isLoadingProducts else { return }
        guard configuration.includesPurchase else {
            entitlementState = .notEntitled
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: configuration.productIDs)
            guard Set(loaded.map(\.id)) == configuration.productIDs else {
                products = []
                message = AppLocalization.string("purchase.productUnavailable", locale: AppLocalization.selectedLocale)
                showingError = true
                await refreshEntitlements()
                return
            }
            products = loaded
        } catch {
            present(error)
        }
        await refreshEntitlements()
    }

    func purchasePrimary() async {
        guard let product = primaryProduct else {
            message = AppLocalization.string("purchase.productUnavailable", locale: AppLocalization.selectedLocale)
            showingError = true
            return
        }
        await purchase(productID: product.id)
    }

    func purchase(productID: String) async {
        guard !isPurchasing, !isRestoring, configuration.productIDs.contains(productID),
              let product = products.first(where: { $0.id == productID }) else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                message = AppLocalization.string("purchase.pending", locale: AppLocalization.selectedLocale)
                showingError = true
            case .userCancelled:
                break
            @unknown default:
                entitlementState = .notEntitled
            }
        } catch {
            present(error)
        }
    }

    func restore() async {
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            present(error)
        }
    }

    func refreshEntitlements() async {
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

        if productIDs.isEmpty,
           !subscriptionResult.isAuthoritative,
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
                present(error)
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
            present(error)
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
        guard configuration.includesSubscription, !subscriptionProducts.isEmpty else {
            return SubscriptionStatusResult(evaluation: nil, isAuthoritative: false)
        }
        var best: VerifiedSubscriptionEvaluation?
        var relevantVerified = 0
        var allEmpty = true
        for product in subscriptionProducts {
            guard let subscription = product.subscription else { continue }
            let statuses: [Product.SubscriptionInfo.Status]
            do { statuses = try await subscription.status }
            catch { return SubscriptionStatusResult(evaluation: nil, isAuthoritative: false) }
            if !statuses.isEmpty { allEmpty = false }
            for status in statuses {
                guard let transaction = try? verified(status.transaction),
                      let renewal = try? verified(status.renewalInfo),
                      configuration.subscriptionProductIDs.contains(transaction.productID) else { continue }
                relevantVerified += 1
                let condition: SubscriptionCondition
                if transaction.revocationDate != nil {
                    condition = .revoked
                } else {
                    switch status.state {
                    case .subscribed:
                        guard let expiry = transaction.expirationDate else { continue }
                        condition = .subscribed(willAutoRenew: renewal.willAutoRenew, expirationDate: expiry)
                    case .inGracePeriod:
                        guard let expiry = renewal.gracePeriodExpirationDate else { continue }
                        condition = .gracePeriod(expirationDate: expiry)
                    case .inBillingRetryPeriod: condition = .billingRetry
                    case .expired: condition = .expired
                    case .revoked: condition = .revoked
                    default: continue
                    }
                }
                let access = SubscriptionAccessEvaluation.resolve(condition: condition, at: now())
                let effective: SubscriptionCondition = access.grantsAccess ? condition : {
                    switch condition {
                    case .subscribed, .gracePeriod, .offlineCached: return .expired
                    default: return condition
                    }
                }()
                let candidate = VerifiedSubscriptionEvaluation(productID: transaction.productID,
                                                               condition: effective, access: access)
                if best == nil || (!best!.access.grantsAccess && access.grantsAccess) ||
                   (access.effectiveExpiration ?? .distantPast) > (best!.access.effectiveExpiration ?? .distantPast) {
                    best = candidate
                }
            }
        }
        return SubscriptionStatusResult(evaluation: best,
                                        isAuthoritative: allEmpty || relevantVerified > 0)
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

    private func present(_ error: Error) {
        message = error is PurchaseError
            ? AppLocalization.string("purchase.verificationFailed", locale: AppLocalization.selectedLocale)
            : error.localizedDescription
        showingError = true
    }
}

private enum PurchaseError: LocalizedError {
    case failedVerification
    var errorDescription: String? { nil }
}
