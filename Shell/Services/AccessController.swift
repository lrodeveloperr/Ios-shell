import Foundation
import Observation

enum AccessDecision: Equatable, Sendable {
    case allowed
    case checkingEntitlement
    case purchaseRequired
    case usageLimitReached
}

@MainActor
@Observable
final class AccessController {
    let configuration: MonetizationConfiguration
    let purchases: PurchaseService
    let usage: UsageLedger

    init(
        configuration: MonetizationConfiguration = ShellConfiguration.monetization,
        purchases: PurchaseService? = nil,
        usage: UsageLedger? = nil
    ) {
        self.configuration = configuration
        self.purchases = purchases ?? PurchaseService(configuration: configuration)
        self.usage = usage ?? UsageLedger(
            limit: configuration.freeSuccessfulActions,
            window: configuration.usageWindow
        )
    }

    var decision: AccessDecision {
        Self.resolveDecision(
            mode: configuration.mode,
            isEntitled: purchases.isEntitled,
            isChecking: purchases.isChecking,
            hasFreeActionRemaining: usage.hasFreeActionRemaining
        )
    }

    /// True while a verified purchase or subscription is active.
    var isEntitled: Bool { purchases.isEntitled }

    static func resolveDecision(
        mode: MonetizationMode,
        isEntitled: Bool,
        isChecking: Bool,
        hasFreeActionRemaining: Bool
    ) -> AccessDecision {
        switch mode {
        case .free, .ads, .adsWithRemovePurchase, .adsWithSubscription,
             .freemiumWithOneTimeUnlock, .freemiumWithSubscription:
            .allowed
        case .oneTimeUnlock, .subscription:
            if isEntitled { .allowed }
            else if isChecking { .checkingEntitlement }
            else { .purchaseRequired }
        case .usageCapWithOneTimeUnlock, .usageCapWithSubscription:
            if isEntitled || hasFreeActionRemaining { .allowed }
            else if isChecking { .checkingEntitlement }
            else { .usageLimitReached }
        }
    }

    var remainingFreeActions: Int? {
        configuration.includesUsageCap ? usage.remaining : nil
    }

    var shouldShowAd: Bool {
        Self.resolveAdVisibility(
            mode: configuration.mode,
            isEntitled: purchases.isEntitled,
            isChecking: purchases.isChecking
        )
    }

    static func resolveAdVisibility(mode: MonetizationMode, isEntitled: Bool, isChecking: Bool) -> Bool {
        switch mode {
        case .ads:
            true
        case .adsWithRemovePurchase, .adsWithSubscription:
            !isChecking && !isEntitled
        default:
            false
        }
    }

    @discardableResult
    func recordSuccessfulAction(id: String) -> UsageRecordingResult {
        guard configuration.includesUsageCap else { return .notMetered }
        guard !purchases.isEntitled else { return .notMetered }
        return usage.recordSuccessfulAction(id: id)
    }

    /// Re-resolves entitlement from StoreKit and returns the verified result.
    /// Product repositories call this when a paid-only mutation commits so a
    /// Boolean captured when a form opened can never grant access after expiry.
    func resolveEntitlement() async -> Bool {
        await purchases.refreshEntitlements()
        return purchases.isEntitled
    }

    /// Called when the app returns to the foreground.
    func sceneDidBecomeActive() async {
        usage.refresh()
        await purchases.refreshEntitlements()
    }
}
