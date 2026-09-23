import SwiftUI

/// The only boundary a derived app replaces. Product modules receive shell
/// access services without owning navigation, billing, ads, legal, or settings.
///
/// Only `makeCanvas` is required. Every other hook has a no-op default, so a
/// provider written for an earlier shell keeps compiling and behaving the same.
@MainActor
protocol FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView

    /// Product rows inserted into Settings after the shell's purchase and
    /// backup sections. Return `nil` for none.
    func makeSettingsContent(context: FeatureCanvasContext) -> AnyView?

    /// Wraps the whole shell, including its sheets, for app-wide environment
    /// such as `.modelContainer(...)`. Must not alter shell presentation.
    func decorateRoot(_ root: AnyView) -> AnyView

    /// Called once after migrations and the first entitlement resolution.
    func didFinishLaunching(context: FeatureCanvasContext) async

    /// Receives URLs opened by the system (custom schemes, universal links).
    func handleOpenURL(_ url: URL, context: FeatureCanvasContext)
}

extension FeatureCanvasProviding {
    func makeSettingsContent(context: FeatureCanvasContext) -> AnyView? { nil }
    func decorateRoot(_ root: AnyView) -> AnyView { root }
    func didFinishLaunching(context: FeatureCanvasContext) async {}
    func handleOpenURL(_ url: URL, context: FeatureCanvasContext) {}
}

struct FeatureCanvasContext {
    let remainingFreeActions: () -> Int?
    let recordSuccessfulAction: (_ stableActionID: String) -> UsageRecordingResult
    let requestUpgrade: () -> Void
    /// Current verified entitlement. Read it when rendering; use
    /// `resolveEntitlement` when a paid-only mutation commits.
    let isEntitled: @MainActor () -> Bool
    /// The shell's current access decision for the canvas.
    let accessDecision: @MainActor () -> AccessDecision
    /// Re-verifies entitlement with StoreKit and returns the result. Call it
    /// when a paid-only domain mutation commits, never a captured Boolean.
    let resolveEntitlement: @MainActor () async -> Bool
    /// Selects a configured destination by id; unknown ids are ignored.
    let selectDestination: @MainActor (_ destinationID: String) -> Void
    /// The language the app is displaying, for formatting and parsing.
    let locale: @MainActor () -> Locale
}

struct PlaceholderFeatureCanvasProvider: FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView {
        AnyView(FeatureView(destination: destination, context: context))
    }
}

struct FeatureCanvasHost: View {
    let destination: ShellDestination
    let provider: any FeatureCanvasProviding
    @Environment(ShellModel.self) private var model

    @ViewBuilder
    var body: some View {
        switch model.access.decision {
        case .allowed:
            provider.makeCanvas(for: destination, context: model.featureContext)
        case .checkingEntitlement:
            ProgressView("access.checking")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("access.checking"))
        case .purchaseRequired:
            LockedFeatureView(
                titleKey: "access.purchase.title",
                messageKey: "access.purchase.message",
                onUpgrade: { model.paywallPresented = true }
            )
        case .usageLimitReached:
            LockedFeatureView(
                titleKey: "access.limit.title",
                messageKey: "access.limit.message",
                onUpgrade: { model.paywallPresented = true }
            )
        }
    }
}

private struct LockedFeatureView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let onUpgrade: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(titleKey, systemImage: "lock.fill")
        } description: {
            Text(messageKey)
        } actions: {
            Button("upgrade", action: onUpgrade)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
