import SwiftUI

/// The only boundary a derived app replaces. Product modules receive shell
/// access services without owning navigation, billing, ads, legal, or settings.
@MainActor
protocol FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView
}

struct FeatureCanvasContext {
    let accessDecision: () -> AccessDecision
    let remainingFreeActions: () -> Int?
    let recordSuccessfulAction: (_ stableActionID: String) -> UsageRecordingResult
    let requestUpgrade: () -> Void
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

    var body: some View {
        provider.makeCanvas(
            for: destination,
            context: FeatureCanvasContext(
                accessDecision: { model.access.decision },
                remainingFreeActions: { model.access.remainingFreeActions },
                recordSuccessfulAction: { model.access.recordSuccessfulAction(id: $0) },
                requestUpgrade: { model.paywallPresented = true }
            )
        )
    }
}
