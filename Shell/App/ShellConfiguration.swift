import SwiftUI

enum ShellConfiguration {
    static let appName = "GymDay"
    /// #BC002D - researched and confirmed earlier as culturally appropriate
    /// for the Japanese market (kouhaku red/white pairing), not a default pick.
    static let tint = Color(red: 0.737, green: 0.0, blue: 0.176)
    // TODO: replace with GymDay's real support address before release.
    static let supportEmail = "support@example.com"

    // TODO: replace with GymDay's real, published legal documents before release.
    static let legal = LegalConfiguration(
        version: "1",
        privacyURL: URL(string: "https://example.com/#replace-with-privacy-policy")!,
        termsURL: URL(string: "https://example.com/#replace-with-terms-of-use")!
    )

    /// Set to nil when the product does not have a genuine onboarding need.
    /// Published legal links alone do not require a blocking acceptance screen.
    static let onboarding: OnboardingProfile? = .legalOnly

    // TODO: replace shell.pro.* with GymDay's real App Store Connect product
    // IDs once its subscription group exists there.
    static let monetization = MonetizationConfiguration(
        mode: .usageCapWithSubscription,
        freeSuccessfulActions: 5,
        lifetimeProductID: "shell.pro.lifetime",
        subscriptionProductID: "shell.pro.monthly",
        secondarySubscriptionProductIDs: ["shell.pro.annual"]
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
        .init(id: "today", titleKey: "destination.today", symbol: "house"),
        .init(id: "programs", titleKey: "destination.programs", symbol: "calendar"),
        .init(id: "progress", titleKey: "destination.progress", symbol: "chart.bar.fill"),
        .init(id: "routines", titleKey: "destination.routines", symbol: "list.bullet"),
    ]

    /// Only locales with complete app text belong here. The 31-locale shared
    /// terminology baseline is tracked separately in LocalizationBaseline.swift.
    static let supportedLanguages: [AppLanguage] = [
        .init(id: "system", displayName: "システムの言語に従う"),
        .init(id: "ja", displayName: "日本語"),
        .init(id: "en", displayName: "English"),
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
    /// Additional products in the same App Store Connect subscription group
    /// as `subscriptionProductID` (e.g. an annual option alongside monthly).
    /// Empty by default, so every existing single-product derived app is
    /// unaffected. `PurchaseService.subscriptionOptions` surfaces these for
    /// a picker; `subscriptionProductID` alone still drives `primaryProduct`
    /// and every existing single-product call site.
    let secondarySubscriptionProductIDs: Set<String>

    init(
        mode: MonetizationMode,
        freeSuccessfulActions: Int,
        lifetimeProductID: String,
        subscriptionProductID: String,
        secondarySubscriptionProductIDs: Set<String> = []
    ) {
        self.mode = mode
        self.freeSuccessfulActions = freeSuccessfulActions
        self.lifetimeProductID = lifetimeProductID
        self.subscriptionProductID = subscriptionProductID
        self.secondarySubscriptionProductIDs = secondarySubscriptionProductIDs
    }

    var productIDs: Set<String> {
        switch mode {
        case .adsWithRemovePurchase, .oneTimeUnlock, .usageCapWithOneTimeUnlock:
            [lifetimeProductID]
        case .adsWithSubscription, .subscription, .usageCapWithSubscription:
            [subscriptionProductID].union(secondarySubscriptionProductIDs)
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
    /// Defaults to `.large`, matching every existing derived app unchanged.
    /// See "Navigation and adaptation" in AGENTS.md before choosing `.inline`.
    var titleDisplayMode: DestinationTitleDisplayMode = .large

    init(id: String, titleKey: String, symbol: String, titleDisplayMode: DestinationTitleDisplayMode = .large) {
        self.id = id
        self.titleKey = titleKey
        self.symbol = symbol
        self.titleDisplayMode = titleDisplayMode
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A Sendable-safe mirror of `NavigationBarItem.TitleDisplayMode` so
/// `ShellConfiguration.destinations` stays a plain, testable value type.
///
/// Large titles are Apple's default for a top-level/tab-root screen and cost
/// roughly 50pt of vertical space versus inline; that's the right trade for a
/// spacious, Western-leaning product. It's the wrong trade for a product
/// whose target market or content density wants that space back — e.g. an
/// app localized for a market where dense information reads as trustworthy
/// rather than sparse reads as calm (see the Japanese-market density
/// discussion in this app's own design notes: generous whitespace there can
/// read as unfinished, not elegant). Choose per destination, not globally;
/// a single derived app can reasonably mix both.
enum DestinationTitleDisplayMode: Sendable {
    case automatic
    case large
    case inline

    var swiftUIValue: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .automatic: .automatic
        case .large: .large
        case .inline: .inline
        }
    }
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
