import GoogleMobileAds
import SwiftUI

@main
struct ShellApp: App {
    init() {
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ShellRootView()
                .tint(ShellConfiguration.tint)
        }
    }
}
