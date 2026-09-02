import SwiftUI

struct ShellLabView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onResetOnboarding: () -> Void

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Monetization") {
                Picker("Mode", selection: $model.monetizationMode) {
                    ForEach(MonetizationMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.navigationLink)
                Toggle("Entitlement / remove ads", isOn: $model.entitlementOverride)
            }
            Section("Feature state") {
                Picker("State", selection: $model.contentState) {
                    ForEach(SampleContentState.allCases) { state in Text(state.title).tag(state) }
                }
                .pickerStyle(.segmented)
            }
            Section("Responsive checks") {
                LabeledContent("Compact", value: "Tab bar")
                LabeledContent("Regular", value: "Sidebar-adaptable tabs")
                LabeledContent("Detail", value: "Split at 700 pt")
                LabeledContent("Ad", value: model.shouldShowAd ? "Reserved safe-area inset" : "Removed; content expands")
            }
            Section {
                Button("Reset onboarding", systemImage: "arrow.counterclockwise") {
                    onResetOnboarding()
                    dismiss()
                }
            }
        }
        .navigationTitle("Shell Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
