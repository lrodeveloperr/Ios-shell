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
        let identifier = SupportedLocaleResolver.localeIdentifier(
            selection: selection,
            preferredLanguages: Locale.preferredLanguages
        )
        return Locale(identifier: identifier)
    }

    private static func resourceLanguage(for locale: Locale) -> String {
        SupportedLocaleResolver.closestSupported(to: locale.identifier)
    }
}
