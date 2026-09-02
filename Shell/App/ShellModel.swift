import Observation
import SwiftUI

@MainActor
@Observable
final class ShellModel {
    var selectedDestination = ShellConfiguration.destinations.first!.id
    var monetizationMode = MonetizationMode.adsWithRemovePurchase
    var contentState = SampleContentState.populated
    var entitlementOverride = false
    var settingsPresented = false
    var labPresented = false

    var shouldShowAd: Bool {
        !entitlementOverride && (monetizationMode == .ads || monetizationMode == .adsWithRemovePurchase)
    }
}
