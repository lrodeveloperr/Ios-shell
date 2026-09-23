# Shell migration protocol

The compiled shell contract is `ShellContract.currentVersion`. A derived app records the installed contract in `UserDefaults` and must supply ordered `ShellMigration` steps for any breaking upgrade.

## Adopt 2.0.0

1. Choose `Shell` for no advertising or `ShellAds` for an app whose reviewed monetization mode includes ads.
2. Keep GAD/SKAdNetwork metadata only in `Info-Ads.plist`; never copy it into `Info.plist`.
3. Remove every app logo, icon, named brand image and app-name hero from commerce surfaces. Run `scripts/check-commerce-branding.sh` when execution is authorized.
4. Leave `backup.enabled` false unless the app adds a reviewed `NativeBackupProviding` implementation, iCloud entitlement, privacy disclosure, serialization version and rollback-safe conflict behavior.
5. Advertise a locale only after all shell, product, legal and store text is translated and reviewed. `LocalizationBaseline` is terminology scope, not proof of completion.
6. Add a migration closure before changing persistent product schema. Each step must be idempotent, preserve a recoverable copy when practical, and update the stored contract version only after success.

Example:

```swift
static let migrations: [ShellMigration] = [
    ShellMigration(fromVersion: "2.0.0", toVersion: "3.0.0") {
        try ProductStore.migrateToVersion3()
    }
]
```

Never silently skip a missing step or erase user data to resolve a migration failure.

Only a MAJOR contract change requires a step. A MINOR or PATCH upgrade is recorded directly, so a compatible shell update can never strand users on the "Update required" screen. Version the product's own persistent schema separately (for example with SwiftData `VersionedSchema`); the shell contract version describes shell storage only.

## Adopt the unreleased 2.x additions

These changes keep the 2.0.0 contract and need no migration step. Existing providers compile unchanged because every new hook has a default.

1. Move identity into `Config/App.xcconfig`: set `APP_DISPLAY_NAME`, `APP_BUNDLE_ID`, `APP_ADS_BUNDLE_ID`, `DEVELOPMENT_TEAM`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; remove those settings from `project.yml`; set `CFBundleDisplayName` to `$(APP_DISPLAY_NAME)` in both plists. `ShellConfiguration.appName` now reads the bundle.
2. Add the new `ShellConfiguration` members: `onboardingTourPages`, `paywallBenefitKeys` and `keychainAccessGroup` (use the template defaults to keep current behavior).
3. Create `ShellModel` once in `ShellApp` (`@State private var model = ShellModel()`) and pass it to `ShellRootView`.
4. Replace every tab `symbol:` use outside the initializer with `icon` (`.system` or `.asset`).
5. Add the new localization keys from `en.lproj` (and `Localizable.stringsdict`) to every shipped catalog.
6. Usage records migrate automatically from the `successful-actions-v1` Keychain item to `successful-actions-v2`; existing usage keeps counting toward a lifetime limit.
7. Delete any `.lproj` folder whose language is not in `supportedLanguages`; the validator now rejects it.
