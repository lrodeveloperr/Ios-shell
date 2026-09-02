import SwiftUI

struct ShellRootView: View {
    private let featureProvider: any FeatureCanvasProviding
    @State private var model: ShellModel
    @State private var legalConsent: LegalConsentStore

    init(
        featureProvider: any FeatureCanvasProviding,
        model: ShellModel = ShellModel(),
        legalConsent: LegalConsentStore = LegalConsentStore()
    ) {
        self.featureProvider = featureProvider
        _model = State(initialValue: model)
        _legalConsent = State(initialValue: legalConsent)
    }

    var body: some View {
        Group {
            if legalConsent.requiresPresentation {
                OnboardingView(
                    profile: ShellConfiguration.onboarding,
                    isReconsent: legalConsent.isReconsent,
                    onAccept: legalConsent.acceptCurrentLegalVersion
                )
            } else {
                shell
            }
        }
        .environment(model)
        .environment(model.language)
        .environment(\.locale, model.language.locale)
        .sheet(isPresented: $model.settingsPresented) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $model.labPresented) {
            NavigationStack { ShellLabView(onResetOnboarding: legalConsent.resetForTesting) }
        }
        .sheet(isPresented: $model.paywallPresented) {
            NavigationStack { PaywallView() }
        }
        .alert("Access", isPresented: $model.accessAlertPresented) {
            Button("ok") {}
        } message: {
            Text(model.accessAlertMessage)
        }
        .task {
            await model.start()
            if !legalConsent.requiresPresentation { await model.prepareAdvertisingIfNeeded() }
        }
        .onChange(of: legalConsent.requiresPresentation) { _, requiresPresentation in
            if !requiresPresentation { Task { await model.prepareAdvertisingIfNeeded() } }
        }
        .onChange(of: model.access.shouldShowAd) { _, shouldShowAd in
            if shouldShowAd && !legalConsent.requiresPresentation {
                Task { await model.prepareAdvertisingIfNeeded() }
            }
        }
    }

    @ViewBuilder
    private var shell: some View {
        if ShellConfiguration.destinations.count == 1, let destination = ShellConfiguration.destinations.first {
            NavigationStack {
                FeatureCanvasHost(destination: destination, provider: featureProvider)
                    .navigationTitle(destination.titleKey)
                    .shellSettingsToolbar()
            }
            .safeAreaInset(edge: .bottom) { adBanner }
        } else {
            TabView(selection: $model.selectedDestination) {
                ForEach(ShellConfiguration.destinations) { destination in
                    NavigationStack {
                        FeatureCanvasHost(destination: destination, provider: featureProvider)
                            .navigationTitle(destination.titleKey)
                            .shellSettingsToolbar()
                    }
                    .tag(destination.id)
                    .tabItem { Label(destination.titleKey, systemImage: destination.symbol) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
        }
    }

    @ViewBuilder
    private var adBanner: some View {
        if model.shouldRenderAd {
            AdaptiveAdBanner(adUnitID: ShellConfiguration.advertising.bannerUnitID)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityLabel(Text("advertisement"))
        }
    }
}

private extension View {
    func shellSettingsToolbar() -> some View { modifier(ShellSettingsToolbar()) }
}

private struct ShellSettingsToolbar: ViewModifier {
    @Environment(ShellModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("settings", systemImage: "gearshape") { model.settingsPresented = true }
                    .labelStyle(.iconOnly)
            }
        }
    }
}
