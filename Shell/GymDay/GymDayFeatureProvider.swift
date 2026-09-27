import GymDayCore
import SwiftUI

/// The product-side implementation of the shell's one extension point.
/// Real Today/Programs/Progress/Routines screens are separate, not-yet-
/// started work; this proves the engine is actually reachable from the UI.
struct GymDayFeatureProvider: FeatureCanvasProviding {
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView {
        AnyView(GymDayDestinationPlaceholder(destination: destination))
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
                    Text("\(snapshot.profiles.count) profile(s), \(snapshot.programs.count) program(s)")
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
