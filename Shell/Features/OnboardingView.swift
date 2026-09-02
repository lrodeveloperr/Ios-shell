import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0
    @State private var legalDocument: LegalDocument?

    private let pages = [
        OnboardingPage(number: "01", title: "A faster starting point", message: "Adaptive navigation, settings, legal, monetization seams, and polished states are ready."),
        OnboardingPage(number: "02", title: "Native on every screen", message: "iPhone uses a familiar tab bar. iPad and larger windows gain a customizable sidebar automatically."),
        OnboardingPage(number: "03", title: "Skin it, then build", message: "Change tokens and configuration first. Replace placeholder features only after your product logic is settled."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(ShellConfiguration.appName)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(pages[page].number)
                .font(.headline)
                .foregroundStyle(.tint)
            Text(pages[page].title)
                .font(.largeTitle.bold())
            Text(pages[page].message)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button(page == pages.count - 1 ? "Get started" : "Continue") {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { onComplete() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Button("Privacy") { legalDocument = .privacy }
                Spacer()
                Button("Terms") { legalDocument = .terms }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalView(document: document) }
        }
    }
}

private struct OnboardingPage {
    let number: String
    let title: String
    let message: String
}
