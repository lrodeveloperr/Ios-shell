import SwiftUI

struct ShellRootView: View {
    @AppStorage("shell.onboardingComplete") private var onboardingComplete = false
    @State private var model = ShellModel()

    var body: some View {
        Group {
            if onboardingComplete {
                shell
            } else {
                OnboardingView { onboardingComplete = true }
            }
        }
        .environment(model)
        .sheet(isPresented: $model.settingsPresented) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $model.labPresented) {
            NavigationStack { ShellLabView(onResetOnboarding: { onboardingComplete = false }) }
        }
    }

    @ViewBuilder
    private var shell: some View {
        if ShellConfiguration.destinations.count == 1, let destination = ShellConfiguration.destinations.first {
            NavigationStack {
                FeatureView(destination: destination)
                    .navigationTitle(destination.title)
                    .shellSettingsToolbar()
            }
            .safeAreaInset(edge: .bottom) { adBanner }
        } else {
            TabView(selection: $model.selectedDestination) {
                ForEach(ShellConfiguration.destinations) { destination in
                    NavigationStack {
                        FeatureView(destination: destination)
                            .navigationTitle(destination.title)
                            .shellSettingsToolbar()
                    }
                    .tag(destination.id)
                    .tabItem { Label(destination.title, systemImage: destination.symbol) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
        }
    }

    @ViewBuilder
    private var adBanner: some View {
        if model.shouldShowAd {
            AdaptiveAdBanner()
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityLabel("Advertisement")
        }
    }
}

private extension View {
    func shellSettingsToolbar() -> some View {
        modifier(ShellSettingsToolbar())
    }
}

private struct ShellSettingsToolbar: ViewModifier {
    @Environment(ShellModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { model.settingsPresented = true }
                    .labelStyle(.iconOnly)
            }
        }
    }
}
