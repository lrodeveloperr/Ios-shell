import GymDayCore
import SwiftUI

/// The real Routines screen: a saved-routine library, backed by
/// GymDayEngine.saveRoutine/deleteRoutine. No per-set editor yet, so a new
/// routine is a name plus a movement checklist - GymDayStore.saveRoutine
/// fills in a plain default prescription per movement.
struct GymDayRoutinesView: View {
    @Environment(GymDayStore.self) private var store
    @State private var isPresentingNewRoutine = false

    var body: some View {
        List {
            if let routines = store.snapshot?.routines, !routines.isEmpty {
                Section {
                    ForEach(routines) { routine in
                        routineRow(routine)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let routine = routines[index]
                            Task { await store.deleteRoutine(routine.id) }
                        }
                    }
                }
            } else {
                ContentUnavailableView("routines.empty", systemImage: "list.bullet")
            }
            if let error = store.routineError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewRoutine = true
                } label: {
                    Label("routines.add", systemImage: "plus")
                }
                .accessibilityIdentifier("gymday.routines.add")
            }
        }
        .sheet(isPresented: $isPresentingNewRoutine) {
            NavigationStack {
                NewRoutineView()
            }
        }
    }

    private func routineRow(_ routine: PersonalRoutine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(routine.name).font(.subheadline.weight(.semibold))
            Text("\(routine.items.count)種目")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NewRoutineView: View {
    @Environment(GymDayStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedMovementIDs: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("routines.name.title") {
                TextField("routines.name.placeholder", text: $name)
            }
            Section("routines.movements.title") {
                ForEach(store.availableMovements, id: \.id) { movement in
                    Toggle(isOn: movementBinding(movement.id)) {
                        Text(movement.japaneseName)
                    }
                }
            }
            if let error = store.routineError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("routines.add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        isSaving = true
                        if await store.saveRoutine(name: name, movementIDs: Array(selectedMovementIDs)) {
                            dismiss()
                        }
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("done")
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedMovementIDs.isEmpty || isSaving)
                .accessibilityIdentifier("gymday.routines.save")
            }
        }
    }

    private func movementBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedMovementIDs.contains(id) },
            set: { isOn in
                if isOn { selectedMovementIDs.insert(id) } else { selectedMovementIDs.remove(id) }
            }
        )
    }
}
