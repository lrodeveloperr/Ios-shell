import GymDayCore
import SwiftUI

/// The workout-in-progress screen: prepares/resumes today's session on
/// appear, lists its items with a way to log sets or skip, and finishes
/// the session once every item is resolved (completed or skipped).
struct ActiveWorkoutView: View {
    @Environment(GymDayStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plannedSessionID: UUID
    let programID: UUID

    var body: some View {
        content
            .navigationTitle("activeWorkout.title")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.activeSession == nil {
                    await store.startWorkout(plannedSessionID: plannedSessionID, programID: programID)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let session = store.activeSession {
            List {
                Section {
                    ForEach(session.items) { item in
                        itemRow(item, session: session)
                    }
                }
                if let error = store.activeWorkoutError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task {
                            if await store.finishWorkout() {
                                store.endActiveWorkout()
                                dismiss()
                            }
                        }
                    } label: {
                        Text("activeWorkout.finish").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("gymday.activeWorkout.finish")
                }
            }
        } else if let error = store.activeWorkoutError {
            ContentUnavailableView {
                Label("error.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func itemRow(_ item: WorkoutItemRecord, session: WorkoutSessionRecord) -> some View {
        NavigationLink {
            SetLoggingView(itemID: item.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if item.status == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if item.status == .skipped {
                    Image(systemName: "arrow.uturn.forward.circle").foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            if !item.status.isTerminal {
                Button("activeWorkout.skip", role: .destructive) {
                    Task { await store.skipItem(itemID: item.id) }
                }
            }
        }
    }

    private func title(for item: WorkoutItemRecord) -> String {
        switch item.content {
        case let .strength(prescription):
            store.movementName(for: prescription.movementID)
        case let .cardio(prescription):
            GymDayDisplay.cardioLabel(prescription.machine)
        }
    }
}
