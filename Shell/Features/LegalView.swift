import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy, terms
    var id: Self { self }
    var titleKey: LocalizedStringKey { self == .privacy ? "privacyPolicy" : "termsOfUse" }
    var bodyKey: LocalizedStringKey { self == .privacy ? "legal.privacy.body" : "legal.terms.body" }
}

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.bodyKey)
                Link("legal.openReviewedDocument", destination: document == .privacy ? ShellConfiguration.legal.privacyURL : ShellConfiguration.legal.termsURL)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(document.titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } } }
    }
}
