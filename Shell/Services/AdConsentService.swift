import GoogleMobileAds
import Observation
import UserMessagingPlatform

@MainActor
@Observable
final class AdConsentService {
    private(set) var canRequestAds = false
    private(set) var isPrivacyOptionsRequired = false
    private(set) var isGatheringConsent = false
    private(set) var initializationComplete = false
    private(set) var preparationAttempted = false
    var message: String?

    func prepareIfNeeded(advertisingEnabled: Bool) async {
        guard advertisingEnabled, !preparationAttempted else { return }
        preparationAttempted = true
        isGatheringConsent = true
        defer { isGatheringConsent = false }

        do {
            try await requestConsentUpdate()
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            updateStateAndStartIfAllowed()
        } catch {
            // Fail closed: no SDK start and no ad request after consent errors.
            canRequestAds = false
            preparationAttempted = false
            isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            message = error.localizedDescription
        }
    }

    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            updateStateAndStartIfAllowed()
        } catch {
            message = error.localizedDescription
        }
    }

    private func requestConsentUpdate() async throws {
        let parameters = RequestParameters()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func updateStateAndStartIfAllowed() {
        message = nil
        canRequestAds = ConsentInformation.shared.canRequestAds
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard canRequestAds, !initializationComplete else { return }
        initializationComplete = true
        MobileAds.shared.start()
    }
}
