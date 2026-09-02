import Foundation
import Observation

@MainActor
@Observable
final class LanguageController {
    private let defaults: UserDefaults
    private let key = "shell.language"
    var selection: String {
        didSet { defaults.set(selection, forKey: key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: key) ?? "system"
    }

    var locale: Locale {
        selection == "system" ? .autoupdatingCurrent : Locale(identifier: selection)
    }
}
