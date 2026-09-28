import SwiftUI

/// The only boundary a derived app replaces. Product modules receive shell
/// access services without owning billing, ads, legal, settings or top-level tabs.
@MainActor
protocol FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView

    /// Return a split canvas for list-detail products. The shell owns the
    /// NavigationSplitView so iPhone collapse and iPad multi-column behavior stay
    /// consistent across derived apps. Return nil for a conventional stack.
    func makeSplitCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> FeatureSplitCanvas?
}

extension FeatureCanvasProviding {
    func makeSplitCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> FeatureSplitCanvas? {
        nil
    }
}

struct FeatureCanvasContext {
    let remainingFreeActions: () -> Int?
    let recordSuccessfulAction: (_ stableActionID: String) -> UsageRecordingResult
    let requestUpgrade: () -> Void
}

/// Type-erased two-column feature contract. Selection is a stable product-owned
/// String so the shell can restore it per scene without knowing domain types.
struct FeatureSplitCanvas {
    let sidebar: (_ selection: Binding<String?>) -> AnyView
    let detail: (_ selection: String?) -> AnyView
}

struct PlaceholderFeatureCanvasProvider: FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView {
        AnyView(FeatureView(destination: destination, context: context))
    }

    func makeSplitCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> FeatureSplitCanvas? {
        FeatureSplitCanvas(
            sidebar: { selection in
                AnyView(FeatureSplitSidebar(destination: destination, context: context, selection: selection))
            },
            detail: { selection in
                AnyView(FeatureSplitDetail(selection: selection))
            }
        )
    }
}

struct FeatureCanvasHost: View {
    let destination: ShellDestination
    let provider: any FeatureCanvasProviding
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ShellModel.self) private var model
    @SceneStorage private var splitSelection: String?

    init(destination: ShellDestination, provider: any FeatureCanvasProviding) {
        self.destination = destination
        self.provider = provider
        _splitSelection = SceneStorage("shell.splitSelection.\(destination.id)")
    }

    @ViewBuilder
    var body: some View {
        switch model.access.decision {
        case .allowed:
            allowedCanvas
        case .checkingEntitlement:
            navigationStack {
                ProgressView("access.checking")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("access.checking"))
            }
        case .purchaseRequired:
            navigationStack {
                LockedFeatureView(
                    titleKey: "access.purchase.title",
                    messageKey: "access.purchase.message",
                    onUpgrade: { model.requestUpgrade() },
                    actionKey: upgradeActionKey,
                    productDescription: subscriptionProductDescription,
                    isBusy: upgradeIsBusy
                )
            }
        case .usageLimitReached:
            navigationStack {
                LockedFeatureView(
                    titleKey: "access.limit.title",
                    messageKey: "access.limit.message",
                    onUpgrade: { model.requestUpgrade() },
                    actionKey: upgradeActionKey,
                    productDescription: subscriptionProductDescription,
                    isBusy: upgradeIsBusy
                )
            }
        }
    }

    @ViewBuilder
    private var allowedCanvas: some View {
        let context = featureContext
        if let split = provider.makeSplitCanvas(for: destination, context: context) {
            NavigationSplitView {
                split.sidebar($splitSelection)
                    .navigationTitle(Text(LocalizedStringKey(destination.titleKey)))
                    .shellSettingsToolbar()
                    .accessibilityIdentifier("shell.feature.split.sidebar")
            } detail: {
                NavigationStack {
                    split.detail(splitSelection)
                        .shellSettingsToolbar(isEnabled: horizontalSizeClass == .compact)
                        .accessibilityIdentifier("shell.feature.split.detail")
                }
            }
        } else {
            navigationStack {
                provider.makeCanvas(for: destination, context: context)
            }
        }
    }

    private var featureContext: FeatureCanvasContext {
        FeatureCanvasContext(
            remainingFreeActions: { model.access.remainingFreeActions },
            recordSuccessfulAction: { model.access.recordSuccessfulAction(id: $0) },
            requestUpgrade: { model.requestUpgrade() }
        )
    }

    private func navigationStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(Text(LocalizedStringKey(destination.titleKey)))
                .shellSettingsToolbar()
        }
    }

    private var upgradeActionKey: LocalizedStringKey {
        guard model.access.configuration.includesSubscription else { return "upgrade" }
        if case .billingRetry = model.access.purchases.subscriptionCondition { return "subscription.manage" }
        return "subscription.viewOffer"
    }

    private var subscriptionProductDescription: String? {
        guard model.access.configuration.includesSubscription else { return nil }
        let description = model.access.purchases.primaryProduct?.description
        return description?.isEmpty == false ? description : nil
    }

    private var upgradeIsBusy: Bool {
        model.access.configuration.includesSubscription && model.access.purchases.isLoadingProducts
    }
}

private struct LockedFeatureView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let onUpgrade: () -> Void
    let actionKey: LocalizedStringKey
    let productDescription: String?
    let isBusy: Bool

    var body: some View {
        ContentUnavailableView {
            Label(titleKey, systemImage: "lock.fill")
        } description: {
            VStack(spacing: 8) {
                Text(messageKey)
                if let productDescription { Text(productDescription) }
            }
        } actions: {
            Button(action: onUpgrade) {
                if isBusy { ProgressView() }
                else { Text(actionKey) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            .accessibilityIdentifier("shell.access.upgrade")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
