import SwiftUI

struct SettingsView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.access.configuration.includesPurchase {
                Section {
                    NavigationLink { PaywallView() } label: {
                        SettingsLabel("upgrade", subtitle: "upgrade.subtitle", symbol: "sparkles")
                    }
                }
            }

            Section {
                NavigationLink { LanguageView() } label: {
                    SettingsLabel("language", subtitle: languageSubtitle, symbol: "globe")
                }
                Link(destination: URL(string: "mailto:\(ShellConfiguration.supportEmail)")!) {
                    SettingsLabel("support", subtitle: ShellConfiguration.supportEmail, symbol: "questionmark.circle")
                }
                if model.access.configuration.includesAdvertising && model.ads.isPrivacyOptionsRequired {
                    Button {
                        Task { await model.ads.presentPrivacyOptions() }
                    } label: {
                        SettingsLabel("privacyOptions", subtitle: "privacyOptions.subtitle", symbol: "hand.raised.square")
                    }
                }
                if model.access.configuration.includesAdvertising && model.ads.message != nil {
                    Button {
                        Task { await model.prepareAdvertisingIfNeeded() }
                    } label: {
                        SettingsLabel("privacyRetry", subtitle: "privacyRetry.subtitle", symbol: "arrow.clockwise")
                    }
                }
            }

            Section("legal") {
                NavigationLink { LegalView(document: .privacy) } label: {
                    SettingsLabel("privacyPolicy", symbol: "hand.raised")
                }
                NavigationLink { LegalView(document: .terms) } label: {
                    SettingsLabel("termsOfUse", symbol: "doc.text")
                }
            }

#if DEBUG
            Section("development") {
                Button {
                    dismiss()
                    Task { @MainActor in model.labPresented = true }
                } label: {
                    SettingsLabel("shellLab", subtitle: "shellLab.subtitle", symbol: "testtube.2")
                }
            }
#endif

            Section {
                Text("settings.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
        }
    }

    private var languageSubtitle: String {
        ShellConfiguration.supportedLanguages.first { $0.id == model.language.selection }?.displayName ?? "Follow system"
    }
}

private struct SettingsLabel: View {
    let titleKey: LocalizedStringKey
    let subtitle: String?
    let symbol: String

    init(_ titleKey: LocalizedStringKey, subtitle: String? = nil, symbol: String) {
        self.titleKey = titleKey
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey).foregroundStyle(.primary)
                if let subtitle { Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

private struct LanguageView: View {
    @Environment(LanguageController.self) private var language

    var body: some View {
        @Bindable var language = language
        Form {
            Picker("language", selection: $language.selection) {
                ForEach(ShellConfiguration.supportedLanguages) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .pickerStyle(.inline)
            Text("language.help")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("language")
    }
}
