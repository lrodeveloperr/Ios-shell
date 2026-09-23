import SafariServices
import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy, terms
    var id: Self { self }
    var url: URL { self == .privacy ? ShellConfiguration.legal.privacyURL : ShellConfiguration.legal.termsURL }

    /// The published translation for the displayed language, when configured.
    func url(forLanguage languageID: String) -> URL {
        self == .privacy
            ? ShellConfiguration.legal.privacyURL(forLanguage: languageID)
            : ShellConfiguration.legal.termsURL(forLanguage: languageID)
    }
}

/// Always shows the published source of truth instead of duplicating legal copy
/// that can become stale or ship as a template placeholder.
struct LegalView: UIViewControllerRepresentable {
    let document: LegalDocument
    var languageID: String? = nil

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let url = languageID.map(document.url(forLanguage:)) ?? document.url
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(ShellConfiguration.tint)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
