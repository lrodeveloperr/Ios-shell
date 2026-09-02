import Observation

@MainActor
@Observable
final class ShellModel {
    var selectedDestination = ShellConfiguration.destinations.first?.id ?? ""
    var contentState = SampleContentState.populated
    var settingsPresented = false
    var labPresented = false
    var paywallPresented = false
    var accessAlertPresented = false
    var accessAlertMessage = ""

    let access: AccessController
    let ads: AdConsentService
    let language: LanguageController

    init(
        access: AccessController = AccessController(),
        ads: AdConsentService = AdConsentService(),
        language: LanguageController = LanguageController()
    ) {
        self.access = access
        self.ads = ads
        self.language = language
    }

    var shouldRenderAd: Bool {
        access.shouldShowAd && ads.canRequestAds
    }

    func start() async {
        await access.purchases.start()
    }

    func prepareAdvertisingIfNeeded() async {
        await ads.prepareIfNeeded(advertisingEnabled: access.shouldShowAd)
    }

    func handleDeniedAccess(_ decision: AccessDecision) {
        switch decision {
        case .allowed:
            return
        case .checkingEntitlement:
            accessAlertMessage = "Checking App Store access. Try again in a moment."
            accessAlertPresented = true
        case .purchaseRequired, .usageLimitReached:
            paywallPresented = true
        }
    }
}
