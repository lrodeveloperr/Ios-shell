import SwiftUI

struct OnboardingView: View {
    let profile: OnboardingProfile
    let isReconsent: Bool
    let onAccept: () -> Void

    @State private var page = 0
    @State private var accepted = false
    @State private var legalDocument: LegalDocument?

    private let tourPages = [
        OnboardingPage(titleKey: "onboarding.tour.fast.title", messageKey: "onboarding.tour.fast.message"),
        OnboardingPage(titleKey: "onboarding.tour.native.title", messageKey: "onboarding.tour.native.message"),
        OnboardingPage(titleKey: "onboarding.tour.ready.title", messageKey: "onboarding.tour.ready.message"),
    ]

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
                    .toggleStyle(.checkbox)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityHint(Text("onboarding.accept.hint"))
                    .accessibilityIdentifier("shell.onboarding.accept")
                }

                Button(primaryButtonTitle) { advanceOrAccept() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(showsAcceptance && !accepted)
                    .accessibilityIdentifier("shell.onboarding.primary")

                if profile == .guidedTour && !isReconsent && page < tourPages.count - 1 {
                    Button("onboarding.skip") {
                        withAnimation { page = tourPages.count - 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }

                if profile == .guidedTour && page > 0 {
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
                .frame(minHeight: 44)
            }
            .frame(maxWidth: 640, minHeight: 540)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document)
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
                Text("\(page + 1) / \(tourPages.count)").font(.headline).foregroundStyle(.tint)
                Text(tourPages[page].titleKey).font(.largeTitle.bold())
                Text(tourPages[page].messageKey).font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private var showsAcceptance: Bool {
        isReconsent || profile != .guidedTour || page == tourPages.count - 1
    }

    private var primaryButtonTitle: LocalizedStringKey {
        profile == .guidedTour && !isReconsent && page < tourPages.count - 1 ? "continue" : "getStarted"
    }

    private func advanceOrAccept() {
        if profile == .guidedTour && !isReconsent && page < tourPages.count - 1 {
            withAnimation { page += 1 }
        } else if accepted {
            onAccept()
        }
    }
}

private struct OnboardingPage {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
}
