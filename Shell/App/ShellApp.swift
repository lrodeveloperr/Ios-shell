import SwiftUI

@main
@MainActor
struct ShellApp: App {
    @State private var bench = BenchAppModel()
    var body: some Scene {
        WindowGroup {
            ShellRootView(featureProvider: CNCFeatureProvider(bench: bench))
                .tint(ShellConfiguration.tint)
                .preferredColorScheme(.light)
        }
    }
}
