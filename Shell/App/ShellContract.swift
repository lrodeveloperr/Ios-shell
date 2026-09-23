import Foundation

enum ShellContract {
    /// Increment MAJOR when a derived app must supply a migration or change its
    /// feature-provider/configuration contract. MINOR and PATCH changes are
    /// recorded without requiring a migration step.
    static let currentVersion = "2.0.0"
    static let storedVersionKey = "shell.contract.version"

    static func majorComponent(of version: String) -> String {
        version.split(separator: ".").first.map(String.init) ?? version
    }
}

struct ShellMigration: Sendable {
    let fromVersion: String
    let toVersion: String
    let apply: @MainActor @Sendable () throws -> Void
}

enum ShellMigrationError: LocalizedError {
    case missingStep(from: String, to: String)
    case cycle(version: String)

    var errorDescription: String? {
        switch self {
        case let .missingStep(from, to):
            AppLocalization.string("startup.migration.missingStep %@ %@", locale: AppLocalization.selectedLocale, from, to)
        case let .cycle(version):
            AppLocalization.string("startup.migration.cycle %@", locale: AppLocalization.selectedLocale, version)
        }
    }
}

@MainActor
final class ShellMigrationManager {
    private let defaults: UserDefaults
    private let currentVersion: String

    init(defaults: UserDefaults = .standard, currentVersion: String = ShellContract.currentVersion) {
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    func migrateIfNeeded(using steps: [ShellMigration]) throws {
        guard let installed = defaults.string(forKey: ShellContract.storedVersionKey) else {
            defaults.set(currentVersion, forKey: ShellContract.storedVersionKey)
            return
        }
        guard installed != currentVersion else { return }

        // Only a MAJOR change is breaking. A compatible upgrade is recorded
        // directly so it can never strand users behind a missing step.
        if ShellContract.majorComponent(of: installed) == ShellContract.majorComponent(of: currentVersion),
           !steps.contains(where: { $0.fromVersion == installed }) {
            defaults.set(currentVersion, forKey: ShellContract.storedVersionKey)
            return
        }

        var cursor = installed
        var visited = Set<String>()
        while cursor != currentVersion {
            guard visited.insert(cursor).inserted else { throw ShellMigrationError.cycle(version: cursor) }
            guard let step = steps.first(where: { $0.fromVersion == cursor }) else {
                throw ShellMigrationError.missingStep(from: cursor, to: currentVersion)
            }
            try step.apply()
            cursor = step.toVersion
            defaults.set(cursor, forKey: ShellContract.storedVersionKey)
        }
    }
}
