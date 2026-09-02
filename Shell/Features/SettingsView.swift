import SwiftUI

struct SettingsView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.monetizationMode != .free {
                Section {
                    NavigationLink {
                        PaywallView()
                    } label: {
                        SettingsLabel("Upgrade", subtitle: "Manage purchases and restore access", symbol: "sparkles")
                    }
                }
            }
            Section {
                NavigationLink { LanguageView() } label: {
                    SettingsLabel("Language", subtitle: "Follow system · English", symbol: "globe")
                }
                Link(destination: URL(string: "mailto:\(ShellConfiguration.supportEmail)")!) {
                    SettingsLabel("Help & support", subtitle: ShellConfiguration.supportEmail, symbol: "questionmark.circle")
                }
            }
            Section("Legal") {
                NavigationLink { LegalView(document: .privacy) } label: {
                    SettingsLabel("Privacy policy", symbol: "hand.raised")
                }
                NavigationLink { LegalView(document: .terms) } label: {
                    SettingsLabel("Terms of use", symbol: "doc.text")
                }
            }
            Section("Development") {
                Button {
                    dismiss()
                    Task { @MainActor in model.labPresented = true }
                } label: {
                    SettingsLabel("Shell Lab", subtitle: "Exercise every reusable state", symbol: "testtube.2")
                }
            }
            Section {
                Text("Shell 1.0 · Replace example URLs, product IDs, ad IDs, and legal text before shipping.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

private struct SettingsLabel: View {
    let title: String
    let subtitle: String?
    let symbol: String

    init(_ title: String, subtitle: String? = nil, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

private struct LanguageView: View {
    @AppStorage("shell.language") private var language = "system"
    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                Text("Follow system").tag("system")
                Text("English").tag("en")
                Text("Español").tag("es")
            }
            .pickerStyle(.inline)
            Text("A derived app can connect this choice to its localization bundle. The shell includes English and Spanish starter strings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Language")
    }
}
