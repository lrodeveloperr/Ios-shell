import SwiftUI

enum ShellConfiguration {
    static let appName = "Shell"
    static let tint = Color.indigo
    static let supportEmail = "support@example.com"

    static let legal = LegalConfiguration(
        version: "1",
        privacyURL: URL(string: "https://example.com/privacy")!,
        termsURL: URL(string: "https://example.com/terms")!
    )

    // `.legalOnly` is the preferred no-tour, one-screen onboarding profile.
    // Every profile still requires the same explicit legal acceptance checkbox.
    static let onboarding: OnboardingProfile = .legalOnly

    static let monetization = MonetizationConfiguration(
        mode: .usageCapWithSubscription,
        freeSuccessfulActions: 5,
        lifetimeProductID: "shell.pro.lifetime",
        subscriptionProductID: "shell.pro.monthly"
    )

    static let advertising = AdvertisingConfiguration(
        bannerUnitID: "ca-app-pub-3940256099942544/2435281174"
    )

    static let destinations: [ShellDestination] = [
        .init(id: "home", titleKey: "destination.home", symbol: "house"),
        .init(id: "library", titleKey: "destination.library", symbol: "tray.full"),
        .init(id: "activity", titleKey: "destination.activity", symbol: "chart.xyaxis.line"),
    ]

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

struct MonetizationConfiguration: Sendable {
    let mode: MonetizationMode
    let freeSuccessfulActions: Int
    let lifetimeProductID: String
    let subscriptionProductID: String

    var productIDs: Set<String> {
        switch mode {
        case .adsWithRemovePurchase, .oneTimeUnlock, .usageCapWithOneTimeUnlock:
            [lifetimeProductID]
        case .subscription, .usageCapWithSubscription:
            [subscriptionProductID]
        case .free, .ads:
            []
        }
    }

    var includesAdvertising: Bool {
        mode == .ads || mode == .adsWithRemovePurchase
    }

    var includesPurchase: Bool {
        !productIDs.isEmpty
    }
}

struct ShellDestination: Hashable, Identifiable, Sendable {
    let id: String
    let titleKey: LocalizedStringKey
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
