# Native iOS application shell

A reusable **100% Swift 6 / SwiftUI** foundation for iPhone and iPad. Product-domain code is injected through `FeatureCanvasProviding`; it does not modify the stable navigation, legal, localization, access, purchase, advertising, or release architecture.

## AI coding tools

Start with [`AGENTS.md`](AGENTS.md). It is the operational source map for the locked shell boundary, safe customization order, feature-provider contract, advertising option, monetization enforcement, localization and release blockers.

## Stable architecture

- Adaptive native `TabView`: one destination has no tab bar; two to five destinations adapt from iPhone tabs to iPad sidebar.
- Optional legal-only, single-screen, or guided onboarding. Set it to `nil` for direct product launch; every enabled profile ends with one explicit acceptance checkbox.
- Legal acceptance version is stored separately from onboarding completion. Incrementing `legal.version` forces re-consent.
- Eight monetization profiles: free, ads, ads with removal purchase, ads with subscription, one-time unlock, subscription, usage cap with one-time unlock, and usage cap with subscription.
- The shell checks access before composing the injected feature canvas, so paid and exhausted-cap functionality cannot appear behind an advisory callback.
- Successful usage is counted only after completion, keyed by a stable product-owned identifier of at most 128 UTF-8 bytes, persisted, and deduplicated.
- StoreKit 2 verification, transaction updates, restore, revocation/expiry handling, and a Keychain offline snapshot whose subscriptions stop at their verified expiry.
- Google UMP consent runs before Google Mobile Ads initialization or any ad request. Required privacy choices remain available in Settings.
- In-app language switching changes the SwiftUI locale immediately and persists.
- Debug-only Shell Lab, automated validation, executed unit tests, and guarded TestFlight upload.

Both GitHub Actions workflows are manual-only so routine commits and pull requests do not consume hosted macOS minutes. Run the validation/build/test workflow deliberately when macOS minutes are available.

## Derive an app

1. Implement `FeatureCanvasProviding` and inject it in `ShellApp`. The shell composes it only when access is allowed; feature code calls `recordSuccessfulAction` only after a confirmed successful capped action.
2. Configure identity, destinations, whether onboarding is needed, legal version/URLs, monetization, product IDs, languages, and advertising in `ShellConfiguration.swift` and `project.yml`.
3. Replace the app icon and the reviewed legal text in every shipped localization.
4. If advertising is enabled, replace both Google demo IDs and complete the AdMob/UMP messages and privacy declarations for the derived app.
5. Create matching App Store Connect products. Product types must match the chosen profile.
6. Run `scripts/validate-shell.sh --release`, `xcodegen generate`, and the unit tests before distribution.

The TestFlight workflow permits template-mode upload only for `com.goodusestudios.shelllab`. Any derived bundle identifier must pass strict release validation before archive or upload.

## Production-only configuration

App Store Connect product records, agreements, pricing, tax/banking state, distribution signing, App Store Connect API secrets, production AdMob IDs and UMP consent messages cannot be safely committed into the reusable shell. The guarded workflow validates source configuration before using those external records.


## Release compliance

Read [the Apple compliance gate](docs/APPLE_STORE_COMPLIANCE.md), [UI regression matrix](docs/UI_REGRESSION_MATRIX.md), [shell changelog](SHELL_CHANGELOG.md), and [migration protocol](MIGRATIONS.md) before deriving or releasing an app.

The default `Shell` target is genuinely ad-free and contains no Google advertising linkage or metadata. `ShellAds` is the explicit opt-in advertising target. Every commerce surface is logo/icon/brand-asset-free and is protected by `scripts/check-commerce-branding.sh`.

The reviewed shared terminology contract is available for 31 locales in `Shell/Resources/gooduse-common-localization-v1.json`. It is not a claim that product-specific or legal text has been translated. Backup remains disabled and entitlement-free until a derived app implements and reviews it. For local-first apps, the preferred manual path is native Files export/import without account sign-in; follow [the backup and usage-integrity guide](docs/BACKUP_AND_USAGE_INTEGRITY.md), especially when a backup coexists with a free-use limit.
