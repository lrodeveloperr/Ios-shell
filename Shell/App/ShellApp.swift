import SwiftUI

@main
struct ShellApp: App {
    var body: some Scene {
        WindowGroup {
            ShellRootView(featureProvider: PlaceholderFeatureCanvasProvider())
                .tint(ShellConfiguration.tint)
        }
    }
}
