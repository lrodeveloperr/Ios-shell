import SwiftUI

enum ShellConfiguration {
    static let appName = "Shell"
    static let tint = Color.indigo
    static let supportEmail = "support@example.com"

    static let legal = LegalConfiguration(
        version: "1",
        privacyURL: URL(string: "https://example.com/#replace-with-privacy-policy")!,
        termsURL: URL(string: "https://example.com/#replace-with-terms-of-use")!
    )

    /// Set to nil when the product does not have a genuine onboarding need.
    /// Published legal links alone do not require a blocking acceptance screen.
    static let onboarding: OnboardingProfile? = .legalOnly

    static let monetization = MonetizationConfiguration(
        mode: .usageCapWithSubscription,
        freeSuccessfulActions: 5,
        lifetimeProductID: "shell.pro.lifetime",
        subscriptionProductID: "shell.pro.monthly"
    )

    static let advertising = AdvertisingConfiguration(
        bannerUnitID: "ca-app-pub-3940256099942544/2435281174"
    )

    /// Cloud is absent by default. A derived app must enable this and inject an
    /// app-owned provider only after privacy, entitlements and conflict UX review.
    static let backup = BackupConfiguration(enabled: false)

    /// New installs record the current contract. Derived apps add an explicit,
    /// ordered step here before adopting a breaking shell contract.
    static let migrations: [ShellMigration] = []

    static let destinations: [ShellDestination] = [
        .init(id: "home", titleKey: "destination.home", symbol: "house"),
        .init(id: "library", titleKey: "destination.library", symbol: "tray.full"),
        .init(id: "activity", titleKey: "destination.activity", symbol: "chart.xyaxis.line"),
    ]

    /// Only locales with complete app text belong here. The 31-locale shared
    /// terminology baseline is tracked separately in LocalizationBaseline.swift.
    static let supportedLanguages: [AppLanguage] = [
        .init(id: "system", displayName: "Follow system"),
        .init(id: "en", displayName: "English"),
        .init(id: "es", displayName: "Español"),
    ]
}

struct LegalConfiguration: Sendable {
    let version: String
    let privacyURL: URL
    let termsURL: URL
}

enum OnboardingProfile: Equatable, Sendable {
    case legalOnly
    case singleScreen
    case guidedTour
}

struct AdvertisingConfiguration: Sendable {
    let bannerUnitID: String
}

struct BackupConfiguration: Sendable {
    let enabled: Bool
}

struct MonetizationConfiguration: Sendable {
    let mode: MonetizationMode
    let freeSuccessfulActions: Int
    let lifetimeProductID: String
    let subscriptionProductID: String

    var productIDs: Set<String> {
        switch mode {
        case .adsWithRemovePurchase, .oneTimeUnlock, .usageCapWithOneTimeUnlock:
            [lifetimeProductID]
        case .adsWithSubscription, .subscription, .usageCapWithSubscription:
            [subscriptionProductID]
        case .free, .ads:
            []
        }
    }

    var includesAdvertising: Bool { mode == .ads || mode == .adsWithRemovePurchase || mode == .adsWithSubscription }
    var includesPurchase: Bool { !productIDs.isEmpty }
    var includesSubscription: Bool { mode == .adsWithSubscription || mode == .subscription || mode == .usageCapWithSubscription }
}

struct ShellDestination: Hashable, Identifiable, Sendable {
    let id: String
    let titleKey: String
    let symbol: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AppLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

enum MonetizationMode: String, CaseIterable, Identifiable, Sendable {
    case free
    case ads
    case adsWithRemovePurchase
    case adsWithSubscription
    case oneTimeUnlock
    case subscription
    case usageCapWithOneTimeUnlock
    case usageCapWithSubscription

    var id: Self { self }
    var title: String {
        switch self {
        case .free: "Free"
        case .ads: "Ads"
        case .adsWithRemovePurchase: "Ads + remove purchase"
        case .adsWithSubscription: "Ads + subscription"
        case .oneTimeUnlock: "One-time unlock"
        case .subscription: "Subscription"
        case .usageCapWithOneTimeUnlock: "Usage cap + one-time unlock"
        case .usageCapWithSubscription: "Usage cap + subscription"
        }
    }
}

enum SampleContentState: String, CaseIterable, Identifiable, Sendable {
    case populated, empty, loading, error
    var id: Self { self }
    var title: String { rawValue.capitalized }
}
