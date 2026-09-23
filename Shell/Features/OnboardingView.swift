import SwiftUI

struct OnboardingView: View {
    let profile: OnboardingProfile
    let isReconsent: Bool
    let onAccept: () -> Void

    @Environment(LanguageController.self) private var language
    @State private var page = 0
    @State private var accepted = false
    @State private var legalDocument: LegalDocument?

    private let tourPages = ShellConfiguration.onboardingTourPages

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(ShellConfiguration.appName).font(.title3.weight(.semibold))
                Spacer(minLength: 32)
                content
                Spacer(minLength: 32)

                if showsAcceptance {
                    Toggle(isOn: $accepted) {
                        Text("onboarding.accept")
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    .accessibilityHint(Text("onboarding.accept.hint"))
                    .accessibilityIdentifier("shell.onboarding.accept")
                }

                Button(primaryButtonTitle) { advanceOrAccept() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(showsAcceptance && !accepted)
                    .accessibilityIdentifier("shell.onboarding.primary")

                if isTour && page > 0 {
                    Button("back") { withAnimation { page -= 1 } }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

                HStack {
                    Button("privacy") { legalDocument = .privacy }
                    Spacer()
                    Button("terms") { legalDocument = .terms }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 640, minHeight: 540)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document, languageID: language.resolvedLanguageID)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isReconsent {
            Image(systemName: "doc.badge.clock").font(.largeTitle).foregroundStyle(.tint)
            Text("onboarding.updatedLegal.title").font(.largeTitle.bold())
            Text("onboarding.updatedLegal.message").font(.title3).foregroundStyle(.secondary)
        } else {
            switch profile {
            case .legalOnly:
                Image(systemName: "checkmark.shield").font(.largeTitle).foregroundStyle(.tint)
                Text("onboarding.legalOnly.title").font(.largeTitle.bold())
                Text("onboarding.legalOnly.message").font(.title3).foregroundStyle(.secondary)
            case .singleScreen:
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
                Text("onboarding.single.title").font(.largeTitle.bold())
                Text("onboarding.single.message").font(.title3).foregroundStyle(.secondary)
            case .guidedTour:
                if let current = tourPages[safe: page] {
                    Text("\(page + 1) / \(tourPages.count)").font(.headline).foregroundStyle(.tint)
                    Text(LocalizedStringKey(current.titleKey)).font(.largeTitle.bold())
                    Text(LocalizedStringKey(current.messageKey)).font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A tour with no configured pages behaves like a legal-only gate.
    private var isTour: Bool { profile == .guidedTour && !tourPages.isEmpty }

    private var isOnLastTourPage: Bool { page >= tourPages.count - 1 }

    private var showsAcceptance: Bool {
        isReconsent || !isTour || isOnLastTourPage
    }

    private var primaryButtonTitle: LocalizedStringKey {
        isTour && !isReconsent && !isOnLastTourPage ? "continue" : "getStarted"
    }

    private func advanceOrAccept() {
        if isTour && !isReconsent && !isOnLastTourPage {
            withAnimation { page += 1 }
        } else if accepted {
            onAccept()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
