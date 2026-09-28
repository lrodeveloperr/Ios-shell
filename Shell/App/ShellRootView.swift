import SwiftUI

struct ShellRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("shell.selectedDestination") private var selectedDestination =
        ShellConfiguration.destinations.first?.id ?? ""

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
            if let startupMessage = model.startupMessage {
                ContentUnavailableView {
                    Label("startup.error.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(startupMessage)
                }
            } else if let onboarding = ShellConfiguration.onboarding,
                      legalConsent.requiresPresentation {
                OnboardingView(
                    profile: onboarding,
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
        .environment(\.layoutDirection, model.language.layoutDirection)
        .sheet(isPresented: $model.settingsPresented) {
            NavigationStack { SettingsView(model: model) }
                .environment(model)
                .environment(model.language)
                .environment(\.locale, model.language.locale)
                .environment(\.layoutDirection, model.language.layoutDirection)
        }
#if DEBUG
        .sheet(isPresented: $model.labPresented) {
            NavigationStack { ShellLabView(onResetOnboarding: legalConsent.resetForTesting) }
                .environment(model)
                .environment(model.language)
                .environment(\.locale, model.language.locale)
                .environment(\.layoutDirection, model.language.layoutDirection)
        }
#endif
        .sheet(isPresented: $model.paywallPresented) {
            NavigationStack { PaywallView(showsDoneButton: true) }
                .environment(model)
                .environment(model.language)
                .environment(\.locale, model.language.locale)
                .environment(\.layoutDirection, model.language.layoutDirection)
        }
        .manageSubscriptionsSheet(isPresented: $model.manageSubscriptionsPresented)
        .alert("store", isPresented: subscriptionErrorBinding) {
            Button("ok") {}
        } message: {
            Text(model.access.purchases.message)
        }
        .task {
            normalizeSelectedDestination()
            await model.start()
            if !requiresOnboarding { await model.prepareAdvertisingIfNeeded() }
        }
        .onChange(of: requiresOnboarding) { _, requiresPresentation in
            if !requiresPresentation { Task { await model.prepareAdvertisingIfNeeded() } }
        }
        .onChange(of: model.access.shouldShowAd) { _, shouldShowAd in
            if shouldShowAd && !requiresOnboarding {
                Task { await model.prepareAdvertisingIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.access.purchases.refreshEntitlements() } }
        }
    }

    private var subscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { model.access.configuration.includesSubscription && !model.settingsPresented && model.access.purchases.showingError },
            set: { model.access.purchases.showingError = $0 }
        )
    }

    private var requiresOnboarding: Bool {
        ShellConfiguration.onboarding != nil && legalConsent.requiresPresentation
    }

    @ViewBuilder
    private var shell: some View {
        if ShellConfiguration.destinations.count == 1, let destination = ShellConfiguration.destinations.first {
            destinationHost(destination)
        } else {
            TabView(selection: $selectedDestination) {
                ForEach(ShellConfiguration.destinations) { destination in
                    Tab(value: destination.id) {
                        destinationHost(destination)
                    } label: {
                        Label(LocalizedStringKey(destination.titleKey), systemImage: destination.symbol)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
    }

    private func destinationHost(_ destination: ShellDestination) -> some View {
        FeatureCanvasHost(destination: destination, provider: featureProvider)
            .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
    }

    @ViewBuilder
    private var adBanner: some View {
        if model.shouldRenderAd {
            AdaptiveAdBanner(
                adUnitID: ShellConfiguration.advertising.bannerUnitID,
                requestsAds: model.ads.canRequestAds
            )
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityLabel(Text("advertisement"))
                .accessibilityIdentifier("shell.ad.slot")
        }
    }

    private func normalizeSelectedDestination() {
        guard !ShellConfiguration.destinations.contains(where: { $0.id == selectedDestination }) else { return }
        selectedDestination = ShellConfiguration.destinations.first?.id ?? ""
    }
}

extension View {
    func shellSettingsToolbar(isEnabled: Bool = true) -> some View {
        modifier(ShellSettingsToolbar(isEnabled: isEnabled))
    }
}

struct ShellSettingsToolbar: ViewModifier {
    @Environment(ShellModel.self) private var model
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            if isEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("settings", systemImage: "gearshape") { model.settingsPresented = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("shell.settings")
                }
            }
        }
    }
}
