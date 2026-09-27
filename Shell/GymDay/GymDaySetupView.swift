import GymDayCore
import SwiftUI

/// First-run setup: collects the minimum `GymProfile` inputs and hands off
/// to `GymDayStore.createProfileAndProgram`. Shown whenever the engine has
/// no profile yet.
struct GymDaySetupView: View {
    @Environment(GymDayStore.self) private var store
    @State private var goal: Goal = .generalFitness
    @State private var experience: ExperienceLevel = .beginner
    @State private var selectedDays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var minutes = 45
    @State private var selectedEquipment: Set<Equipment> = []
    @State private var isSubmitting = false

    private static let equipmentOptions: [Equipment] = [
        .dumbbells, .barbell, .bench, .cableMachine, .selectorizedMachine, .legPress,
    ]

    var body: some View {
        Form {
            Section("setup.goal.title") {
                Picker("setup.goal.title", selection: $goal) {
                    ForEach(Goal.allCases, id: \.self) { option in
                        Text(option.labelKey).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("setup.experience.title") {
                Picker("setup.experience.title", selection: $experience) {
                    ForEach(ExperienceLevel.allCases, id: \.self) { option in
                        Text(option.labelKey).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("setup.days.title") {
                HStack(spacing: 8) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        weekdayButton(day)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Section("setup.minutes.title") {
                Stepper(value: $minutes, in: 20...180, step: 5) {
                    Text("\(minutes)分")
                }
            }

            Section("setup.equipment.title") {
                ForEach(Self.equipmentOptions, id: \.self) { equipment in
                    Toggle(isOn: equipmentBinding(equipment)) {
                        Text(Self.equipmentLabelKey(equipment))
                    }
                }
            }

            if let setupError = store.setupError {
                Section {
                    Text(setupError).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    isSubmitting = true
                    Task {
                        await store.createProfileAndProgram(
                            goal: goal,
                            experience: experience,
                            availableDays: selectedDays,
                            targetSessionMinutes: minutes,
                            equipment: selectedEquipment
                        )
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("setup.submit").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedDays.isEmpty || isSubmitting)
                .accessibilityIdentifier("gymday.setup.submit")
            }
        }
    }

    private func weekdayButton(_ day: Weekday) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            if isSelected { selectedDays.remove(day) } else { selectedDays.insert(day) }
        } label: {
            Text(day.shortLabelKey)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func equipmentBinding(_ equipment: Equipment) -> Binding<Bool> {
        Binding(
            get: { selectedEquipment.contains(equipment) },
            set: { isOn in
                if isOn { selectedEquipment.insert(equipment) } else { selectedEquipment.remove(equipment) }
            }
        )
    }

    /// Only ever called with a member of `equipmentOptions`, the curated
    /// subset this form actually offers.
    private static func equipmentLabelKey(_ equipment: Equipment) -> LocalizedStringKey {
        switch equipment {
        case .dumbbells: "equipment.dumbbells"
        case .barbell: "equipment.barbell"
        case .bench: "equipment.bench"
        case .cableMachine: "equipment.cableMachine"
        case .selectorizedMachine: "equipment.selectorizedMachine"
        case .legPress: "equipment.legPress"
        default: "equipment.dumbbells"
        }
    }
}

private extension Goal {
    var labelKey: LocalizedStringKey {
        switch self {
        case .generalFitness: "goal.generalFitness"
        case .fatLoss: "goal.fatLoss"
        case .muscleGain: "goal.muscleGain"
        case .strength: "goal.strength"
        }
    }
}

private extension ExperienceLevel {
    var labelKey: LocalizedStringKey {
        switch self {
        case .beginner: "experience.beginner"
        case .intermediate: "experience.intermediate"
        }
    }
}

private extension Weekday {
    var shortLabelKey: LocalizedStringKey {
        switch self {
        case .monday: "weekday.monday"
        case .tuesday: "weekday.tuesday"
        case .wednesday: "weekday.wednesday"
        case .thursday: "weekday.thursday"
        case .friday: "weekday.friday"
        case .saturday: "weekday.saturday"
        case .sunday: "weekday.sunday"
        }
    }
}
