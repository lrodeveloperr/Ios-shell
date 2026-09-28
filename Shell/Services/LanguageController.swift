import Foundation
import Observation
import SwiftUI

enum SupportedLocaleResolver {
    static func closestSupported(to candidate: String) -> String {
        let normalized = normalize(candidate)
        let explicit = ShellConfiguration.supportedLanguages.filter { $0.id != "system" }
        if let exact = explicit.first(where: { normalized == normalize($0.id) }) {
            return exact.id
        }
        let base = languageBase(normalized)
        if let languageMatch = explicit.first(where: {
            let supported = normalize($0.id)
            return supported == base || supported.hasPrefix(base + "-")
        }) {
            return languageMatch.id
        }
        return explicit.first(where: { $0.id == "en" })?.id ?? explicit.first?.id ?? "en"
    }

    /// Locale identifier used for formatting and SwiftUI localization. Preserve
    /// the user's regional/script preference only when its language is actually
    /// supported; otherwise format in the real fallback language.
    static func localeIdentifier(selection: String, preferredLanguages: [String]) -> String {
        guard selection == "system" else { return closestSupported(to: selection) }
        let candidate = preferredLanguages.first ?? "en"
        let supported = closestSupported(to: candidate)
        return languageBase(normalize(candidate)) == languageBase(normalize(supported))
            ? candidate
            : supported
    }

    static func resolvedLanguageIdentifier(selection: String, preferredLanguages: [String]) -> String {
        selection == "system"
            ? closestSupported(to: preferredLanguages.first ?? "en")
            : closestSupported(to: selection)
    }

    static func isRightToLeft(_ identifier: String) -> Bool {
        Locale.Language(identifier: identifier).characterDirection == .rightToLeft
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func languageBase(_ identifier: String) -> String {
        identifier.split(separator: "-").first.map(String.init) ?? identifier
    }
}

@MainActor
@Observable
final class LanguageController {
    private let defaults: UserDefaults
    private let preferredLanguages: [String]
    private let key = "shell.language"

    var selection: String {
        didSet { defaults.set(selection, forKey: key) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
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
        Locale(identifier: SupportedLocaleResolver.localeIdentifier(
            selection: selection,
            preferredLanguages: preferredLanguages
        ))
    }

    var layoutDirection: LayoutDirection {
        let language = SupportedLocaleResolver.resolvedLanguageIdentifier(
            selection: selection,
            preferredLanguages: preferredLanguages
        )
        return SupportedLocaleResolver.isRightToLeft(language) ? .rightToLeft : .leftToRight
    }

    static func closestSupported(to candidate: String) -> String {
        SupportedLocaleResolver.closestSupported(to: candidate)
    }
}
