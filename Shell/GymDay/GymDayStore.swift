import Foundation
import GymDayAppleAdapters
import GymDayCore
import Observation
import SwiftData

/// MainActor-observable wrapper around the `GymDayEngine` actor so SwiftUI
/// views can bind to its state the same way they bind to `ShellModel`.
@MainActor
@Observable
final class GymDayStore {
    private(set) var snapshot: EngineSnapshot?
    private(set) var startupError: String?
    private(set) var setupError: String?
    private var engine: GymDayEngine?
    private var catalog: MovementCatalog?

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
            let catalog = try MovementCatalog.launchCatalog()
            self.catalog = catalog
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

    /// The Japanese display name for a movement ID, e.g. from a
    /// `StrengthPrescription`. Falls back to the raw ID if the catalog
    /// hasn't loaded or somehow doesn't contain it.
    func movementName(for id: String) -> String {
        catalog?.movement(id: id)?.japaneseName ?? id
    }

    var activeProgram: TrainingProgram? {
        snapshot?.programs.first { $0.status == .active }
    }

    /// The active program's session scheduled for today, or - if none lands
    /// exactly today - the next upcoming one. `nil` means a genuine rest day
    /// (or the program has no more sessions).
    var todaysSession: PlannedSession? {
        guard let activeProgram else { return nil }
        let allSessions = activeProgram.weeks.flatMap(\.sessions)
        let calendar = Calendar.current
        if let today = allSessions.first(where: { calendar.isDateInToday($0.scheduledDate) }) {
            return today
        }
        return allSessions
            .filter { $0.scheduledDate > Date() }
            .min { $0.scheduledDate < $1.scheduledDate }
    }

    /// First-run setup: creates the profile, then immediately generates and
    /// activates a 6-week program from it. Minimal on purpose - length,
    /// multiple profiles and preferred cardio machines aren't exposed yet.
    func createProfileAndProgram(
        goal: Goal,
        experience: ExperienceLevel,
        availableDays: Set<Weekday>,
        targetSessionMinutes: Int,
        equipment: Set<Equipment>
    ) async {
        guard let engine else { return }
        setupError = nil
        do {
            let profile = try GymProfile(
                goal: goal,
                experience: experience,
                availableDays: availableDays,
                targetSessionMinutes: targetSessionMinutes,
                equipment: equipment,
                preferredCardio: []
            )
            _ = try await engine.addProfile(profile)
            _ = try await engine.createProgram(
                profileID: profile.id,
                length: .six,
                startDate: Date(),
                namespace: "gymday.default"
            )
            snapshot = await engine.currentSnapshot()
        } catch {
            setupError = error.localizedDescription
        }
    }

    /// Bridges the shell's verified StoreKit state into the engine's own
    /// entitlement vocabulary. Deliberately binary (free/pro): GymDayCore's
    /// richer `.expired` + `currentWeekGraceThrough` soft-landing policy
    /// (see `StoreKitEntitlementResolver` in GymDayAppleAdapters) still needs
    /// a notion of the active program's current week, which doesn't exist
    /// yet - that's separate, later work, not approximated here.
    func syncEntitlement(from access: AccessController) async {
        guard let engine else { return }
        let purchases = access.purchases
        var tier: EntitlementTier = .free
        var productID: String?
        var verifiedThrough: Date?

        if purchases.isEntitled {
            tier = .pro
            if access.configuration.includesSubscription {
                // Report whichever product actually granted access (monthly
                // or annual), not always the configured primary/default.
                switch purchases.entitlementState {
                case let .entitled(productIDs), let .offlineCached(productIDs):
                    productID = productIDs.first ?? access.configuration.subscriptionProductID
                case .checking, .notEntitled:
                    productID = access.configuration.subscriptionProductID
                }
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

        // Disambiguate from the shell's own EntitlementSnapshot (EntitlementCache.swift,
        // the Keychain-backed offline-purchase cache) - same name, different module,
        // and same-module lookup wins over the GymDayCore import without this.
        let entitlement = GymDayCore.EntitlementSnapshot(
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
