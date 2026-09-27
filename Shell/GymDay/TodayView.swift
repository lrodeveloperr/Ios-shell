import GymDayCore
import SwiftUI

/// The real Today screen: today's scheduled session from the active
/// program, or a rest-day state. Starting the workout isn't built yet
/// (ActiveWorkout/SetLogging are separate, later work), so the button
/// currently just says so rather than doing nothing silently.
struct TodayView: View {
    @Environment(GymDayStore.self) private var store
    @State private var showsComingSoonAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session = store.todaysSession {
                    sessionCard(session)
                    startButton
                } else {
                    restDayCard
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .alert("today.comingSoon", isPresented: $showsComingSoonAlert) {
            Button("ok") {}
        }
    }

    private func sessionCard(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.items) { item in
                itemRow(item)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func itemRow(_ item: PlannedItem) -> some View {
        switch item.content {
        case let .strength(prescription):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.movementName(for: prescription.movementID))
                        .font(.subheadline.weight(.semibold))
                    if let firstSet = prescription.sets.first {
                        Text("\(prescription.sets.count)セット・\(firstSet.repetitions.lower)〜\(firstSet.repetitions.upper)回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        case let .cardio(prescription):
            HStack {
                Text(Self.cardioLabel(prescription.machine))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(prescription.targetDurationSeconds / 60)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func cardioLabel(_ machine: CardioMachine) -> String {
        switch machine {
        case .treadmill: "トレッドミル"
        case .stationaryBike: "バイク"
        case .rower: "ローイングマシン"
        case .stairClimber: "ステアクライマー"
        case .elliptical: "エリプティカル"
        case .custom: "カーディオ"
        }
    }

    private var startButton: some View {
        Button {
            showsComingSoonAlert = true
        } label: {
            Text("today.startWorkout")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("gymday.today.start")
    }

    private var restDayCard: some View {
        ContentUnavailableView("today.restDay", systemImage: "moon.zzz")
    }
}
