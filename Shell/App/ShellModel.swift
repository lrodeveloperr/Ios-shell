import Observation

@MainActor
@Observable
final class ShellModel {
    var selectedDestination = ShellConfiguration.destinations.first?.id ?? ""
#if DEBUG
    var contentState = SampleContentState.populated
#endif
    var settingsPresented = false
#if DEBUG
    var labPresented = false
#endif
    var paywallPresented = false

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

}
