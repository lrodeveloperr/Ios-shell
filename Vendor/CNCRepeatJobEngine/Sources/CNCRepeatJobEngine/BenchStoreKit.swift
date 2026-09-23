#if canImport(StoreKit)
import Foundation
import StoreKit

public struct BenchOffer: Sendable, Equatable {
    public let productID: String
    public let displayName: String
    public let displayPrice: String
}

public enum BenchPurchaseOutcome: Sendable { case active, pending, cancelled }

/// Host-app purchase boundary. Route every production mutation through apply(_:to:actor:).
/// The engine and backups never store a user-editable "paid" flag. StoreKit's
/// verified current entitlements, including an Apple billing grace period,
/// decide access again at each attempted command.
public actor BenchStoreKit {
    public let monthlyProductID: String
    public let annualProductID: String

    public init(monthlyProductID: String, annualProductID: String) throws {
        guard !monthlyProductID.isEmpty, !annualProductID.isEmpty,
              monthlyProductID != annualProductID else {
            throw BenchError.invalid("Configure distinct monthly and annual App Store product IDs.")
        }
        self.monthlyProductID = monthlyProductID
        self.annualProductID = annualProductID
    }

    public func offers() async throws -> [BenchOffer] {
        let products = try await Product.products(for: [monthlyProductID, annualProductID])
        guard products.count == 2,
              Set(products.map(\.id)) == Set([monthlyProductID, annualProductID]),
              products.allSatisfy({ $0.type == .autoRenewable }) else {
            throw BenchError.missing("Both subscription products must be available in the App Store.")
        }
        return [monthlyProductID, annualProductID].compactMap { id in
            products.first(where: { $0.id == id }).map {
                BenchOffer(productID: $0.id, displayName: $0.displayName,
                           displayPrice: $0.displayPrice)
            }
        }
    }

    public func currentAccess() async -> BenchAccess {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.productID == monthlyProductID || transaction.productID == annualProductID else { continue }
            // Do not compare expirationDate with the device clock: StoreKit
            // includes entitled subscriptions in Apple's billing grace period.
            return .pro
        }
        return .free
    }

    public func purchase(_ productID: String) async throws -> BenchPurchaseOutcome {
        guard productID == monthlyProductID || productID == annualProductID else {
            throw BenchError.invalid("Unknown subscription product.")
        }
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { $0.id == productID && $0.type == .autoRenewable }) else {
            throw BenchError.missing("Subscription product is unavailable.")
        }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            guard transaction.productID == productID, transaction.revocationDate == nil else {
                throw BenchError.blocked("The verified purchase does not grant this subscription.")
            }
            await transaction.finish()
            return await currentAccess() == .pro ? .active : .pending
        case .success(.unverified):
            throw BenchError.blocked("The App Store purchase could not be verified.")
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .pending
        }
    }

    /// Call only after a user taps Restore Purchases; AppStore.sync may prompt for login.
    public func restorePurchases() async throws -> BenchAccess {
        try await AppStore.sync()
        return await currentAccess()
    }

    /// Refreshes StoreKit before every mutation, including approval and run start.
    @discardableResult public func apply(_ command: BenchCommand, to repository: BenchRepository,
                                         actor: String, at: Date = Date(),
                                         operationID: UUID = UUID()) async throws -> BenchState {
        let access = await currentAccess()
        return try await repository.apply(command, actor: actor, at: at,
                                          operationID: operationID, access: access)
    }
}
#endif
