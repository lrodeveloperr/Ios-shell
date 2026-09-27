import Foundation
import GymDayAppleAdapters
import GymDayCore
import Observation
import SwiftData

/// MainActor-observable wrapper around the `GymDayEngine` actor so SwiftUI
/// views can bind to its state the same way they bind to `ShellModel`.
///
/// The movement catalog is still empty - real movement content is separate,
/// not-yet-started work.
@MainActor
@Observable
final class GymDayStore {
    private(set) var snapshot: EngineSnapshot?
    private(set) var startupError: String?
    private var engine: GymDayEngine?

    func start() async {
        guard engine == nil else { return }
        do {
            let configuration = ModelConfiguration(
                schema: Schema(versionedSchema: GymDaySchemaV1.self),
                cloudKitDatabase: .none
            )
            let modelContainer = try ModelContainer(
                for: Schema(versionedSchema: GymDaySchemaV1.self),
                migrationPlan: GymDaySchemaMigrationPlan.self,
                configurations: [configuration]
            )
            let repository = SwiftDataEngineRepository(modelContainer: modelContainer)
            let catalog = try MovementCatalog(movements: [])
            let engine = try await GymDayEngine.open(repository: repository, catalog: catalog, now: Date())
            self.engine = engine
            snapshot = await engine.currentSnapshot()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func refresh() async {
        guard let engine else { return }
        snapshot = await engine.currentSnapshot()
    }

    /// Bridges the shell's verified StoreKit state into the engine's own
    /// entitlement vocabulary. Deliberately binary (free/pro): GymDayCore's
    /// richer `.expired` + `currentWeekGraceThrough` soft-landing policy
    /// (see `StoreKitEntitlementResolver` in GymDayAppleAdapters) needs real
    /// monthly/annual product IDs and active-program week tracking that
    /// don't exist yet - that's separate, later work, not approximated here.
    func syncEntitlement(from access: AccessController) async {
        guard let engine else { return }
        let purchases = access.purchases
        var tier: EntitlementTier = .free
        var productID: String?
        var verifiedThrough: Date?

        if purchases.isEntitled {
            tier = .pro
            if access.configuration.includesSubscription {
                productID = access.configuration.subscriptionProductID
                switch purchases.subscriptionCondition {
                case let .subscribed(_, expirationDate),
                     let .gracePeriod(expirationDate),
                     let .offlineCached(expirationDate):
                    verifiedThrough = expirationDate
                case .notApplicable, .checking, .billingRetry, .expired, .revoked:
                    // isEntitled is true but the subscription condition hasn't
                    // caught up yet (e.g. right after an offline-cache read).
                    // Never silently deny access the shell already granted.
                    verifiedThrough = .distantFuture
                }
            } else {
                // One-time/lifetime purchase: entitled with no expiration.
                productID = access.configuration.lifetimeProductID
                verifiedThrough = .distantFuture
            }
        }

        let entitlement = EntitlementSnapshot(
            tier: tier,
            productID: productID,
            verifiedThrough: verifiedThrough,
            resolvedAt: Date(),
            isVerified: true
        )

        do {
            try await engine.replaceEntitlement(entitlement)
            snapshot = await engine.currentSnapshot()
        } catch {
            startupError = error.localizedDescription
        }
    }
}
