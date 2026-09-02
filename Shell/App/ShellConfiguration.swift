import SwiftUI

enum ShellConfiguration {
    static let appName = "Shell"
    static let tint = Color.indigo
    static let supportEmail = "support@example.com"
    static let privacyURL = URL(string: "https://example.com/privacy")!
    static let termsURL = URL(string: "https://example.com/terms")!
    static let subscriptionProductID = "shell.pro.monthly"
    static let lifetimeProductID = "shell.pro.lifetime"
    static let demoBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    static let destinations: [ShellDestination] = [
        .init(id: "home", title: "Home", symbol: "house"),
        .init(id: "library", title: "Library", symbol: "tray.full"),
        .init(id: "activity", title: "Activity", symbol: "chart.xyaxis.line"),
    ]
}

struct ShellDestination: Hashable, Identifiable {
    let id: String
    let title: String
    let symbol: String
}

enum MonetizationMode: String, CaseIterable, Identifiable {
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

enum SampleContentState: String, CaseIterable, Identifiable {
    case populated, empty, loading, error
    var id: Self { self }
    var title: String { rawValue.capitalized }
}
