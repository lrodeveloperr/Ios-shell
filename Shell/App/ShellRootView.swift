import SwiftUI

struct ShellRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let featureProvider: any FeatureCanvasProviding
    @State private var model: ShellModel
    @State private var legalConsent: LegalConsentStore
    @State private var launchCompleted = false

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
        featureProvider.decorateRoot(AnyView(content))
    }

    private var content: some View {
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
            NavigationStack { SettingsView(model: model, featureProvider: featureProvider) }
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
        .task {
            let started = await model.start()
            if !requiresOnboarding { await model.prepareAdvertisingIfNeeded() }
            if started && !launchCompleted {
                launchCompleted = true
                await featureProvider.didFinishLaunching(context: model.featureContext)
            }
        }
        .onOpenURL { url in
            featureProvider.handleOpenURL(url, context: model.featureContext)
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
            if phase == .active { Task { await model.access.sceneDidBecomeActive() } }
        }
    }

    private var requiresOnboarding: Bool {
        ShellConfiguration.onboarding != nil && legalConsent.requiresPresentation
    }

    @ViewBuilder
    private var shell: some View {
        if ShellConfiguration.destinations.count == 1, let destination = ShellConfiguration.destinations.first {
            destinationStack(destination)
        } else {
            TabView(selection: $model.selectedDestination) {
                ForEach(ShellConfiguration.destinations) { destination in
                    destinationStack(destination)
                    .tag(destination.id)
                    .tabItem { Label(model.language.string(destination.titleKey), icon: destination.icon) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
    }

    private func destinationStack(_ destination: ShellDestination) -> some View {
        NavigationStack {
            FeatureCanvasHost(destination: destination, provider: featureProvider)
                .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
                .navigationTitle(model.language.string(destination.titleKey))
                .shellSettingsToolbar()
        }
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
}

private extension Label where Title == Text, Icon == Image {
    /// One native `Label` for either an SF Symbol or a template asset, as the
    /// iPhone tab bar requires.
    init(_ title: String, icon: DestinationIcon) {
        switch icon {
        case let .system(name): self.init(title, systemImage: name)
        case let .asset(name): self.init(title, image: name)
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
                    .accessibilityIdentifier("shell.settings")
            }
        }
    }
}
