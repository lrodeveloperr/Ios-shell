import SwiftUI

@main
struct ShellApp: App {
    /// Created exactly once so StoreKit listeners and Keychain reads are not
    /// repeated when the scene body is re-evaluated.
    @State private var model = ShellModel()

    var body: some Scene {
        WindowGroup {
            ShellRootView(featureProvider: PlaceholderFeatureCanvasProvider(), model: model)
                .tint(ShellConfiguration.tint)
        }
    }
}
