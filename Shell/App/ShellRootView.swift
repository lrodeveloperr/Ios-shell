import StoreKit
import SwiftUI

struct ShellRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        .confirmationDialog(
            "subscription.subscribe",
            isPresented: $model.subscriptionOptionsPresented,
            titleVisibility: .visible
        ) {
            ForEach(model.access.purchases.subscriptionOptions, id: \.id) { product in
                Button("\(product.displayName) — \(product.displayPrice)") {
                    Task { await model.access.purchases.purchase(productID: product.id) }
                }
            }
            Button("cancel", role: .cancel) {}
        }
        .alert("store", isPresented: subscriptionErrorBinding) {
            Button("ok") {}
        } message: {
            Text(model.access.purchases.message)
        }
        .task {
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
            destinationStack(destination)
        } else if horizontalSizeClass == .regular {
            splitViewShell
        } else {
            tabViewShell
        }
    }

    /// iPhone, and iPad in a compact multitasking width: a native bottom tab
    /// bar, one tab per destination.
    private var tabViewShell: some View {
        TabView(selection: $model.selectedDestination) {
            ForEach(ShellConfiguration.destinations) { destination in
                destinationStack(destination)
                    .tag(destination.id)
                    .tabItem { Label(LocalizedStringKey(destination.titleKey), systemImage: destination.symbol) }
            }
        }
    }

    /// iPad and Mac at regular width: a native sidebar plus detail column.
    private var splitViewShell: some View {
        NavigationSplitView {
            List(ShellConfiguration.destinations, selection: selectionBinding) { destination in
                Label(LocalizedStringKey(destination.titleKey), systemImage: destination.symbol)
                    .tag(destination.id)
            }
            .listStyle(.sidebar)
            .navigationTitle(Text(ShellConfiguration.appName))
        } detail: {
            if let destination = ShellConfiguration.destinations.first(where: { $0.id == model.selectedDestination }) {
                destinationStack(destination)
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedDestination },
            set: { model.selectedDestination = $0 ?? model.selectedDestination }
        )
    }

    private func destinationStack(_ destination: ShellDestination) -> some View {
        NavigationStack {
            FeatureCanvasHost(destination: destination, provider: featureProvider)
                .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
                .navigationTitle(Text(LocalizedStringKey(destination.titleKey)))
                .navigationBarTitleDisplayMode(destination.titleDisplayMode.swiftUIValue)
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
