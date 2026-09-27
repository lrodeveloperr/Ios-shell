import GymDayCore
import SwiftUI

/// The product-side implementation of the shell's one extension point.
/// "today" is real, backed by the engine; Programs/Progress/Routines are
/// still a live placeholder - separate, not-yet-started work.
struct GymDayFeatureProvider: FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView {
        if destination.id == "today" {
            return AnyView(TodayRouterView())
        }
        return AnyView(GymDayDestinationPlaceholder(destination: destination))
    }
}

/// Routes "today" between first-run setup and the real Today content,
/// based on whether a profile exists yet.
private struct TodayRouterView: View {
    @Environment(GymDayStore.self) private var store

    var body: some View {
        if let startupError = store.startupError {
            ContentUnavailableView {
                Label("error.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(startupError)
            }
        } else if let snapshot = store.snapshot {
            if snapshot.profiles.isEmpty {
                GymDaySetupView()
            } else {
                TodayView()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GymDayDestinationPlaceholder: View {
    let destination: ShellDestination
    @Environment(GymDayStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: destination.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(LocalizedStringKey(destination.titleKey))
                .font(.title2.weight(.semibold))
            Group {
                if let startupError = store.startupError {
                    Text(startupError).foregroundStyle(.red)
                } else if let snapshot = store.snapshot {
                    Text("\(snapshot.profiles.count) profile(s), \(snapshot.programs.count) program(s) · \(snapshot.entitlement.tier.rawValue)")
                } else {
                    ProgressView()
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
