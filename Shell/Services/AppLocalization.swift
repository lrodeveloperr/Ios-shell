import Foundation

enum AppLocalization {
    static func string(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        string(key, locale: locale, arguments: arguments)
    }

    static func string(_ key: String, locale: Locale, arguments: [CVarArg]) -> String {
        let language = resourceLanguage(for: locale)
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// Display name for a language option; `system` is always localized.
    static func languageName(_ language: AppLanguage, locale: Locale) -> String {
        language.id == "system" ? string("language.system", locale: locale) : language.displayName
    }

    static var selectedLocale: Locale {
        let selection = UserDefaults.standard.string(forKey: "shell.language") ?? "system"
        return selection == "system" ? .autoupdatingCurrent : Locale(identifier: selection)
    }

    static func resourceLanguage(for locale: Locale) -> String {
        SupportedLocaleResolver.closestSupported(to: locale.identifier)
    }
}
