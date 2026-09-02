import Observation
import StoreKit

enum EntitlementState: Equatable, Sendable {
    case checking
    case entitled(productIDs: Set<String>)
    case offlineCached(productIDs: Set<String>)
    case notEntitled
}

@MainActor
@Observable
final class PurchaseService {
    private let configuration: MonetizationConfiguration
    private let cache: any EntitlementCaching
    private let now: @Sendable () -> Date
    private var updatesTask: Task<Void, Never>?

    private(set) var products: [Product] = []
    private(set) var entitlementState: EntitlementState = .checking
    private(set) var isLoadingProducts = false
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

        if let snapshot = cache.load(), snapshot.isEntitled(to: configuration.productIDs, at: now()) {
            entitlementState = .offlineCached(productIDs: snapshot.entitledProductIDs.intersection(configuration.productIDs))
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

    deinit { updatesTask?.cancel() }

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
        case .subscription, .usageCapWithSubscription:
            desiredID = configuration.subscriptionProductID
        case .free, .ads:
            return nil
        }
        return products.first { $0.id == desiredID }
    }

    func start() async {
        guard configuration.includesPurchase else {
            entitlementState = .notEntitled
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: configuration.productIDs)
        } catch {
            present(error)
        }
        await refreshEntitlements()
    }

    func purchasePrimary() async {
        guard let product = primaryProduct else {
            message = "The App Store product is unavailable. Check the product identifier and App Store Connect state."
            showingError = true
            return
        }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                message = "The purchase is pending approval. Access will update automatically when the App Store completes it."
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

        var productIDs = Set<String>()
        var expiries: [String: Date] = [:]

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result),
                  configuration.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate {
                guard expirationDate > now() else { continue }
                expiries[transaction.productID] = expirationDate
            }
            productIDs.insert(transaction.productID)
        }

        if productIDs.isEmpty {
            entitlementState = .notEntitled
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
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try verified(result)
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

    private func present(_ error: Error) {
        message = error.localizedDescription
        showingError = true
    }
}

private enum PurchaseError: LocalizedError {
    case failedVerification
    var errorDescription: String? { "The App Store transaction could not be verified." }
}
