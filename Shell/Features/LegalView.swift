import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy, terms
    var id: Self { self }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
    var body: String {
        switch self {
        case .privacy:
            "This shell does not collect personal data. Replace this placeholder with the derived app’s reviewed privacy policy, data inventory, retention rules, advertising disclosures, and contact details before distribution."
        case .terms:
            "This shell is a reusable development template. Replace these terms with the derived app’s reviewed terms, purchase conditions, subscription renewal language, and jurisdiction-specific clauses before distribution."
        }
    }
}

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            Text(document.body)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
