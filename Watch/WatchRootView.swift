import SwiftUI

/// Scaffolding placeholder. The real workout-session UI (HKWorkoutSession
/// as primary + WorkoutMirrorTransport mirroring to the phone) lands once
/// this target is confirmed building clean in CI.
struct WatchRootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
            Text("GymDay")
                .font(.headline)
        }
    }
}

#Preview {
    WatchRootView()
}
