import SwiftUI

@main
struct ShellApp: App {
    @State private var gymDayStore = GymDayStore()

    var body: some Scene {
        WindowGroup {
            ShellRootView(featureProvider: GymDayFeatureProvider())
                .environment(gymDayStore)
                .task { await gymDayStore.start() }
                .tint(ShellConfiguration.tint)
        }
    }
}
