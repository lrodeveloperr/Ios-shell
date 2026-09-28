import GymDayCore
import SwiftUI

/// Logs sets against one workout item's prescription. Only strength items
/// have a real logging UI for now; a cardio item falls back to a "not yet"
/// state rather than a broken/incomplete cardio logger.
struct SetLoggingView: View {
    @Environment(GymDayStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID

    private var item: WorkoutItemRecord? {
        store.activeSession?.items.first { $0.id == itemID }
    }

    private var prescription: StrengthPrescription? {
        guard case let .strength(prescription) = item?.content else { return nil }
        return prescription
    }

    var body: some View {
        Group {
            if let prescription {
                List {
                    Section {
                        ForEach(Array(prescription.sets.enumerated()), id: \.element.id) { index, plannedSet in
                            SetRow(
                                itemID: itemID,
                                index: index,
                                plannedSet: plannedSet,
                                logged: item?.strengthSets.first { $0.plannedSetID == plannedSet.id },
                                laterality: store.laterality(for: prescription.movementID)
                            )
                        }
                    }
                    if let error = store.activeWorkoutError {
                        Section {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                    if item?.status != .completed {
                        Section {
                            Button("activeWorkout.completeExercise") {
                                Task {
                                    if await store.completeItem(itemID: itemID) {
                                        dismiss()
                                    }
                                }
                            }
                            .disabled(!(item?.strengthSets.contains { $0.status == .completed } ?? false))
                            .accessibilityIdentifier("gymday.setLogging.complete")
                        }
                    }
                }
            } else {
                ContentUnavailableView("today.comingSoon", systemImage: "hourglass")
            }
        }
        .navigationTitle(Text(store.movementName(for: prescription?.movementID ?? "")))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetRow: View {
    @Environment(GymDayStore.self) private var store
    let itemID: UUID
    let index: Int
    let plannedSet: SetPrescription
    let logged: StrengthSetEntry?
    let laterality: LateralityRule

    @State private var weightKilograms: Double
    @State private var reps: Int
    @State private var isSaving = false

    init(itemID: UUID, index: Int, plannedSet: SetPrescription, logged: StrengthSetEntry?, laterality: LateralityRule) {
        self.itemID = itemID
        self.index = index
        self.plannedSet = plannedSet
        self.logged = logged
        self.laterality = laterality
        let initialWeightGrams = logged?.weightGrams ?? plannedSet.targetWeightGrams ?? 0
        _weightKilograms = State(initialValue: Double(initialWeightGrams) / 1000)
        _reps = State(initialValue: logged?.enteredRepetitions ?? plannedSet.repetitions.lower)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("セット\(index + 1)・\(plannedSet.repetitions.lower)〜\(plannedSet.repetitions.upper)回")
                .font(.subheadline.weight(.semibold))
            Stepper(value: $weightKilograms, in: 0...500, step: 1.25) {
                Text(String(format: "%.2fkg", weightKilograms))
            }
            Stepper(value: $reps, in: 0...50) {
                Text("\(reps)回")
            }
            Button {
                Task {
                    isSaving = true
                    if let entry = try? StrengthSetEntry(
                        plannedSetID: plannedSet.id,
                        status: .completed,
                        type: plannedSet.type,
                        weightGrams: Int64((weightKilograms * 1000).rounded()),
                        enteredRepetitions: reps,
                        laterality: laterality,
                        source: SourceAttribution(kind: .manualPhone),
                        updatedAt: Date()
                    ) {
                        await store.logSet(itemID: itemID, entry: entry)
                    }
                    isSaving = false
                }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text(logged == nil ? "activeWorkout.logSet" : "activeWorkout.updateSet")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)
            .accessibilityIdentifier("gymday.setLogging.logSet.\(index)")
            if logged?.status == .completed {
                Label("activeWorkout.setLogged", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
