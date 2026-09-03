import Foundation

enum AppLocalization {
    static func string(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        let language = resourceLanguage(for: locale)
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: locale, arguments: arguments)
    }

    static var selectedLocale: Locale {
        let selection = UserDefaults.standard.string(forKey: "shell.language") ?? "system"
        return selection == "system" ? .autoupdatingCurrent : Locale(identifier: selection)
    }

    private static func resourceLanguage(for locale: Locale) -> String {
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let explicit = ShellConfiguration.supportedLanguages.filter { $0.id != "system" }
        if let exact = explicit.first(where: {
            normalized == $0.id.lowercased() || normalized.hasPrefix($0.id.lowercased() + "-")
        }) { return exact.id }
        let base = normalized.split(separator: "-").first.map(String.init) ?? "en"
        if let languageMatch = explicit.first(where: {
            $0.id.lowercased() == base || $0.id.lowercased().hasPrefix(base + "-")
        }) { return languageMatch.id }
        return explicit.first(where: { $0.id == "en" })?.id ?? explicit.first?.id ?? "en"
    }
}
