import SwiftUI

@main
struct ShellApp: App {
    @State private var gymDayStore = GymDayStore()
    @State private var shellModel = ShellModel()

    var body: some Scene {
        WindowGroup {
            ShellRootView(featureProvider: GymDayFeatureProvider(), model: shellModel)
                .environment(gymDayStore)
                .task {
                    await gymDayStore.start()
                    await gymDayStore.syncEntitlement(from: shellModel.access)
                }
                .onChange(of: shellModel.access.purchases.entitlementState) { _, _ in
                    Task { await gymDayStore.syncEntitlement(from: shellModel.access) }
                }
                .onChange(of: shellModel.access.purchases.subscriptionCondition) { _, _ in
                    Task { await gymDayStore.syncEntitlement(from: shellModel.access) }
                }
                .tint(ShellConfiguration.tint)
        }
    }
}
