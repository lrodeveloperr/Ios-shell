import SwiftUI

enum ShellConfiguration {
    /// Resolved from `APP_DISPLAY_NAME` in `Config/App.xcconfig` through the
    /// Info.plist, so the app name has exactly one source of truth.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }

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

    /// Pages shown by the `.guidedTour` profile. Replace the keys with reviewed
    /// product copy; the final page always carries the acceptance control.
    static let onboardingTourPages: [OnboardingPage] = [
        OnboardingPage(titleKey: "onboarding.tour.fast.title", messageKey: "onboarding.tour.fast.message"),
        OnboardingPage(titleKey: "onboarding.tour.native.title", messageKey: "onboarding.tour.native.message"),
        OnboardingPage(titleKey: "onboarding.tour.ready.title", messageKey: "onboarding.tour.ready.message"),
    ]

    static let monetization = MonetizationConfiguration(
        mode: .usageCapWithSubscription,
        freeSuccessfulActions: 5,
        lifetimeProductID: "shell.pro.lifetime",
        subscriptionProductID: "shell.pro.monthly"
    )

    /// Benefits listed on the paywall. Each must name an entitlement the selected
    /// mode and StoreKit product actually grant; replace with product copy.
    static let paywallBenefitKeys: [String] = monetization.defaultPaywallBenefitKeys

    static let advertising = AdvertisingConfiguration(
        bannerUnitID: "ca-app-pub-3940256099942544/2435281174"
    )

    /// Cloud is absent by default. A derived app must enable this and inject an
    /// app-owned provider only after privacy, entitlements and conflict UX review.
    static let backup = BackupConfiguration(enabled: false)

    /// Set to a shared keychain access group (for example an app-extension
    /// group) only when a widget or extension must read entitlement or usage.
    /// Changing it after release orphans items stored under the previous group.
    static let keychainAccessGroup: String? = nil

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
    /// The `system` entry is always presented through the `language.system` key.
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
    /// Optional published translations keyed by `supportedLanguages` id. A
    /// language without an entry falls back to the default URL.
    let localizedPrivacyURLs: [String: URL]
    let localizedTermsURLs: [String: URL]

    init(
        version: String,
        privacyURL: URL,
        termsURL: URL,
        localizedPrivacyURLs: [String: URL] = [:],
        localizedTermsURLs: [String: URL] = [:]
    ) {
        self.version = version
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.localizedPrivacyURLs = localizedPrivacyURLs
        self.localizedTermsURLs = localizedTermsURLs
    }

    func privacyURL(forLanguage languageID: String) -> URL {
        localizedPrivacyURLs[languageID] ?? privacyURL
    }

    func termsURL(forLanguage languageID: String) -> URL {
        localizedTermsURLs[languageID] ?? termsURL
    }
}

enum OnboardingProfile: Equatable, Sendable {
    case legalOnly
    case singleScreen
    case guidedTour
}

struct OnboardingPage: Hashable, Sendable {
    let titleKey: String
    let messageKey: String
}

struct AdvertisingConfiguration: Sendable {
    let bannerUnitID: String
}

struct BackupConfiguration: Sendable {
    let enabled: Bool
}

/// Calendar window in which free successful actions are counted.
enum UsageWindow: String, Sendable {
    /// The limit never resets.
    case lifetime
    /// The limit resets at the start of each local calendar day.
    case day
    /// The limit resets at the start of each local calendar month.
    case month
}

struct MonetizationConfiguration: Sendable {
    let mode: MonetizationMode
    let freeSuccessfulActions: Int
    let usageWindow: UsageWindow
    let lifetimeProductID: String
    let subscriptionProductID: String
    /// Further auto-renewable products in the same subscription group, for
    /// example a yearly plan offered beside `subscriptionProductID`.
    let additionalSubscriptionProductIDs: [String]
    /// Shows Apple's offer-code redemption sheet on the paywall.
    let offersCodeRedemption: Bool

    init(
        mode: MonetizationMode,
        freeSuccessfulActions: Int,
        usageWindow: UsageWindow = .lifetime,
        lifetimeProductID: String,
        subscriptionProductID: String,
        additionalSubscriptionProductIDs: [String] = [],
        offersCodeRedemption: Bool = false
    ) {
        self.mode = mode
        self.freeSuccessfulActions = freeSuccessfulActions
        self.usageWindow = usageWindow
        self.lifetimeProductID = lifetimeProductID
        self.subscriptionProductID = subscriptionProductID
        self.additionalSubscriptionProductIDs = additionalSubscriptionProductIDs
        self.offersCodeRedemption = offersCodeRedemption
    }

    /// Subscription products in paywall display order.
    var subscriptionProductIDs: [String] {
        var ordered = [subscriptionProductID]
        for id in additionalSubscriptionProductIDs where !ordered.contains(id) { ordered.append(id) }
        return ordered
    }

    /// Purchasable products for the selected mode, in paywall display order.
    var orderedProductIDs: [String] {
        switch mode {
        case .adsWithRemovePurchase, .oneTimeUnlock, .usageCapWithOneTimeUnlock, .freemiumWithOneTimeUnlock:
            [lifetimeProductID]
        case .adsWithSubscription, .subscription, .usageCapWithSubscription, .freemiumWithSubscription:
            subscriptionProductIDs
        case .free, .ads:
            []
        }
    }

    var productIDs: Set<String> { Set(orderedProductIDs) }

    var includesAdvertising: Bool { mode == .ads || mode == .adsWithRemovePurchase || mode == .adsWithSubscription }
    var includesPurchase: Bool { !productIDs.isEmpty }
    var includesSubscription: Bool {
        mode == .adsWithSubscription || mode == .subscription || mode == .usageCapWithSubscription || mode == .freemiumWithSubscription
    }
    var includesUsageCap: Bool { mode == .usageCapWithOneTimeUnlock || mode == .usageCapWithSubscription }

    /// Template benefit list that only claims what the selected mode grants.
    var defaultPaywallBenefitKeys: [String] {
        var keys: [String] = []
        if mode != .adsWithRemovePurchase && mode != .adsWithSubscription && includesPurchase {
            keys.append("paywall.benefit.unlimited")
        }
        if includesAdvertising { keys.append("paywall.benefit.noAds") }
        keys.append("paywall.benefit.support")
        return keys
    }
}

/// A tab or sidebar icon. Both cases render through a native `Label`, which the
/// iPhone tab bar requires; custom drawings belong in the asset catalog.
enum DestinationIcon: Hashable, Sendable {
    /// An SF Symbol name.
    case system(String)
    /// A template-rendered image in `Assets.xcassets`.
    case asset(String)
}

struct ShellDestination: Hashable, Identifiable, Sendable {
    let id: String
    let titleKey: String
    let icon: DestinationIcon

    init(id: String, titleKey: String, symbol: String) {
        self.init(id: id, titleKey: titleKey, icon: .system(symbol))
    }

    init(id: String, titleKey: String, image: String) {
        self.init(id: id, titleKey: titleKey, icon: .asset(image))
    }

    init(id: String, titleKey: String, icon: DestinationIcon) {
        self.id = id
        self.titleKey = titleKey
        self.icon = icon
    }

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
    /// The canvas is always available; the product repository enforces its own
    /// free-tier limits through `FeatureCanvasContext` entitlement checks.
    case freemiumWithOneTimeUnlock
    /// The canvas is always available; the product repository enforces its own
    /// free-tier limits through `FeatureCanvasContext` entitlement checks.
    case freemiumWithSubscription

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
        case .freemiumWithOneTimeUnlock: "Freemium + one-time unlock"
        case .freemiumWithSubscription: "Freemium + subscription"
        }
    }
}

enum SampleContentState: String, CaseIterable, Identifiable, Sendable {
    case populated, empty, loading, error
    var id: Self { self }
    var title: String { rawValue.capitalized }
}
