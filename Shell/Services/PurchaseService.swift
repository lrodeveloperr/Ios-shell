import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseService {
    private(set) var products: [Product] = []
    private(set) var isEntitled = false
    var showingError = false
    var message = ""

    var primaryProduct: Product? { products.first }

    func load() async {
        do {
            products = try await Product.products(for: [
                ShellConfiguration.subscriptionProductID,
                ShellConfiguration.lifetimeProductID,
            ]).sorted { $0.price < $1.price }
            await refreshEntitlements()
        } catch {
            present(error)
        }
    }

    func purchasePrimary() async {
        guard let product = primaryProduct else {
            message = "Configure matching products in App Store Connect to exercise a real purchase."
            showingError = true
            return
        }
        do {
            let result = try await product.purchase()
            if case let .success(verification) = result {
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
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

    private func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? verified(result), transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
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
