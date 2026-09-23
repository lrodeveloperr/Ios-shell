import SwiftUI
import Observation

enum SupportedLocaleResolver {
    static func closestSupported(to candidate: String) -> String {
        let normalized = candidate.replacingOccurrences(of: "_", with: "-").lowercased()
        let explicit = ShellConfiguration.supportedLanguages.filter { $0.id != "system" }
        if let exact = explicit.first(where: { normalized == $0.id.lowercased() }) {
            return exact.id
        }
        let base = normalized.split(separator: "-").first.map(String.init) ?? "en"
        if let languageMatch = explicit.first(where: {
            $0.id.lowercased() == base || $0.id.lowercased().hasPrefix(base + "-")
        }) { return languageMatch.id }
        return explicit.first(where: { $0.id == "en" })?.id ?? explicit.first?.id ?? "system"
    }

    static func isRightToLeft(_ identifier: String) -> Bool {
        let base = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)?.lowercased() ?? identifier.lowercased()
        return ["ar", "dv", "fa", "he", "ku", "ps", "ur", "yi"].contains(base)
    }
}

@MainActor
@Observable
final class LanguageController {
    private let defaults: UserDefaults
    private let key = "shell.language"
    var selection: String {
        didSet { defaults.set(selection, forKey: key) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let supported = ShellConfiguration.supportedLanguages.map(\.id)
        if let stored = defaults.string(forKey: key), supported.contains(stored) {
            selection = stored
        } else if supported.contains("system") {
            selection = "system"
        } else {
            selection = Self.closestSupported(to: preferredLanguages.first ?? "en")
        }
    }

    var locale: Locale {
        selection == "system" ? .autoupdatingCurrent : Locale(identifier: selection)
    }

    /// Direction of the catalog actually shown. Following the system on a
    /// device whose language has no shipped catalog displays the fallback
    /// language, so the direction follows that fallback, not the device.
    var layoutDirection: LayoutDirection {
        SupportedLocaleResolver.isRightToLeft(resolvedLanguageID) ? .rightToLeft : .leftToRight
    }

    /// The `supportedLanguages` id whose catalog is displayed.
    var resolvedLanguageID: String {
        selection == "system" ? Self.closestSupported(to: Locale.autoupdatingCurrent.identifier) : selection
    }

    /// Resolves a shell or product key in the selected language.
    func string(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.string(key, locale: locale, arguments: arguments)
    }

    static func closestSupported(to candidate: String) -> String {
        SupportedLocaleResolver.closestSupported(to: candidate)
    }
}
