# AI implementation guide

This repository is a reusable **native Apple-platform shell**. It is Swift 6 and SwiftUI only. The shell owns repetitive application infrastructure; a derived app supplies its product logic through `FeatureCanvasProviding`.

Read this file before changing code.

## Non-negotiable architecture

- Keep the application 100% Swift and SwiftUI.
- Do not introduce Flutter, React Native, UIKit screen architecture, WebView application shells or another cross-platform runtime.
- Preserve native navigation, safe areas, Dynamic Type, VoiceOver, RTL and iPhone/iPad adaptation.
- Keep private user data local unless the derived product specification explicitly authorizes a service.
- Do not fork or duplicate shell screens inside product code.
- Never bypass `AccessController` or compose the feature canvas before access is allowed.
- Never grant paid access from a UI flag, transaction callback alone, unverified StoreKit result or expired snapshot.
- GitHub Actions and TestFlight workflows are manual-only. Never trigger either unless the user explicitly requests it.

## Five-minute source map

| Concern | Authoritative source |
|---|---|
| Per-app configuration | `Shell/App/ShellConfiguration.swift` |
| App entry point | `Shell/App/ShellApp.swift` |
| Root navigation and shell composition | `Shell/App/ShellRootView.swift` |
| Replaceable product boundary | `Shell/App/FeatureCanvasBoundary.swift` |
| Example product canvas | `Shell/Features/FeatureView.swift` |
| Onboarding and legal | `Shell/Features/OnboardingView.swift`, `LegalView.swift` |
| Settings and paywall | `Shell/Features/SettingsView.swift`, `PaywallView.swift` |
| Access and usage cap | `Shell/Services/AccessController.swift`, `UsageLedger.swift` |
| StoreKit and offline entitlement | `Shell/Services/PurchaseService.swift`, `EntitlementCache.swift` |
| Ads and consent | `Shell/Services/AdaptiveAdBanner.swift`, `AdConsentService.swift` |
| Legal consent | `Shell/Services/LegalConsentStore.swift` |
| Language selection | `Shell/Services/LanguageController.swift` |
| Identity, package and target | `project.yml`, `Shell/Resources/Info.plist` |
| Icons and colors | `Shell/Resources/Assets.xcassets` |
| Release checks | `scripts/validate-shell.sh`, `scripts/check-commerce-branding.sh` |
| Apple compliance gate | `docs/APPLE_STORE_COMPLIANCE.md` |
| UI regression matrix | `docs/UI_REGRESSION_MATRIX.md` |
| Shell version and migrations | `Shell/App/ShellContract.swift`, `SHELL_CHANGELOG.md`, `MIGRATIONS.md` |
| Optional native backup seam | `Shell/Services/NativeBackup.swift` |
| Shared 31-locale terms | `Shell/Resources/gooduse-common-localization-v1.json` |
| Localization release checklist | `docs/LOCALIZATION_RELEASE_CHECKLIST.md` |
| Derived-app release wiring | `docs/DERIVED_APP_RELEASE_WIRING.md` |

## What a derived app may replace

A derived app normally changes only:

1. Identity: bundle ID, product name, version, SKU and App Store identifiers.
2. Brand: complete AppIcon set, in-app mark, tint and product-specific copy.
3. `ShellConfiguration`: legal URLs/version, onboarding, destinations, languages, monetization, product IDs, ads and support address.
4. The product implementation conforming to `FeatureCanvasProviding`.
5. Product-specific localization, SwiftData models/repositories and Apple capabilities that the product truly needs.
6. Reviewed privacy, terms, privacy manifest and store metadata.

Everything else is shell infrastructure. Modify it only to fix a platform-wide defect that should benefit every future app.

## Required implementation order

1. Write the product flow and identify exactly which operations count as successful billable actions.
2. Select one monetization mode in `ShellConfiguration.swift`.
3. Configure bundle identity, legal version, HTTPS links, support, destinations, languages and onboarding.
4. Replace the complete icon/brand family.
5. Implement the feature provider and local data layer.
6. Record a successful action only after the domain operation commits successfully.
7. Configure matching App Store Connect products and advertising, when applicable.
8. Replace every template placeholder and finish localization. Rewrite the complete paywall title, message and benefit list around the derived app's actual paid outcome; generic shell claims such as “useful thing” or “core actions” are release blockers.
9. Review the privacy manifest and store disclosures against actual behavior.
10. Perform only the validation or upload explicitly authorized for the task.

Do not redesign settled shell UI while implementing the product canvas.

## Feature-canvas contract

- Conform to `FeatureCanvasProviding` and inject the provider into `ShellApp`.
- The host checks access before calling the provider.
- A stable action ID represents one completed domain operation and must be at most 128 UTF-8 bytes.
- Record success after persistence succeeds, never on button press, form opening, validation failure or retry.
- Reusing the same ID must be safe; `UsageLedger` deduplicates it.
- Present the existing shell paywall when access is exhausted.
- Product code must not read or mutate StoreKit or Keychain entitlement state directly.

## Monetization modes

| Mode | Access | Advertising | Required product |
|---|---|---|---|
| `.free` | Always | No | None |
| `.ads` | Always | Yes | None |
| `.adsWithRemovePurchase` | Always | Until verified unlock | One-time |
| `.adsWithSubscription` | Always | Until verified subscription | Subscription |
| `.oneTimeUnlock` | Verified purchase only | No | One-time |
| `.subscription` | Active verified subscription only | No | Subscription |
| `.usageCapWithOneTimeUnlock` | Free successful actions, then verified unlock | No | One-time |
| `.usageCapWithSubscription` | Free successful actions, then active subscription | No | Subscription |

The current template default is `.usageCapWithSubscription` with five free successful actions. Change it deliberately for each app.

### Lower ad banner

The anchored adaptive banner is implemented inside each destination's product-content safe area—not on the outer `TabView`. The outer placement clips or displaces the native iPhone tab bar. Its slot must use the height returned by the Mobile Ads SDK for the current width; never force a fixed 50/60-point height around a large adaptive banner. The correctly sized slot is reserved while consent resolves, and an ad request occurs only when all conditions are true:

- the selected monetization mode is `.ads`, `.adsWithRemovePurchase` or `.adsWithSubscription`;
- UMP says ads may be requested;
- Mobile Ads has been prepared; and
- no verified remove-ads entitlement is active.

Usage-cap, one-time-unlock, ad-free subscription and free profiles do not show the banner. Replace Google demo IDs only in an ad-enabled derived app and complete the corresponding UMP, privacy-manifest and App Store disclosures.

## Revenue integrity

- `AccessController` resolves access before the feature provider runs.
- Product IDs and product types must match App Store Connect.
- StoreKit results must pass verification.
- Pending or cancelled purchases do not grant access.
- `Transaction.updates` and `Transaction.currentEntitlements` keep entitlement state current.
- Revoked and expired products are excluded.
- Product loading has a localized terminal failure and retry state; it must never spin forever after loading ends.
- Subscription cache access stops at verified expiry.
- Keychain usage records are durable, bounded and deduplicated.
- Shell Lab and entitlement overrides must remain inside `#if DEBUG`.

## Onboarding and legal

The shell supports `.legalOnly`, `.singleScreen` and `.guidedTour`. The current default is `.legalOnly`. Every profile ends with one explicit acceptance control. Changing the legal version forces re-consent. Privacy and terms must be readable before acceptance.

All onboarding, Settings and paywall legal controls must resolve from `ShellConfiguration.legal` and open the published HTTPS source of truth. Do not duplicate policy bodies in localization files. Before release, verify every configured destination returns a successful page and contains the intended app policy—not merely a non-error placeholder host.

## Navigation and adaptation

- Configure one to five destinations.
- One destination uses a native `NavigationStack` without a tab bar.
- Two to five destinations use adaptive `TabView`; iPhone shows tabs and wider iPad layouts may promote to a sidebar.
- Every `.tabItem` must be a single native `Label` backed by either a valid SF Symbol (`systemImage:`) or a template-rendered asset-catalog image (`image:`).
- Never place a custom `View`, `Canvas`, `Shape`, drawing closure or composed stack directly in `.tabItem`; the native iPhone tab bar may discard it and leave a blank icon. A custom destination icon belongs in `Assets.xcassets` and must be referenced through `Label(..., image:)`.
- A tab-bar UI test must verify that every visible tab button contains an image. Seeing a custom icon inside the product canvas is not evidence that it renders in the native tab bar.
- Preserve safe-area insets and avoid device-model checks.
- The feature canvas owns product content, not global navigation.

## Localization and accessibility

- Keep all shell and product text in localization resources.
- `supportedLanguages` is a release claim. Add a locale there only after the complete product, notification, accessibility, commerce and validation-error catalog passes `docs/LOCALIZATION_RELEASE_CHECKLIST.md`; shared shell terms do not qualify a language.
- Every non-system `supportedLanguages` identifier must have a matching `.lproj` catalog with exact English key parity. Run `python3 scripts/validate-localizations.py`; missing catalogs and key drift block release.
- Keep persisted enum/raw values stable, but map them to localization keys for presentation. Never show `rawValue` as user-facing text.
- Validate a stored language selection against the current shipped catalog on every launch. Removed locales must fall back to `system` when offered, otherwise to the closest enabled language and then English.
- Parse and format numbers, money, dates and quantities with the selected app locale, including comma-decimal input. Use plural rules or reviewed singular/plural keys; never concatenate English grammar.
- Search must recognize localized displayed terminology as well as stored canonical values. Notification copy and accessibility labels must use the selected locale.
- Review region-specific product terminology, text expansion and bidirectional layout before enabling a locale. An RTL language requires an actual RTL pass, not only translated strings.
- Translate domain states by their intended meaning rather than word-for-word labels; validate grammatical agreement across benefit lists and make localized purchase buttons name the concrete entitlement instead of an abstract promise.
- Published policies and store metadata must be reviewed for each enabled locale; otherwise clearly disclose the document language and do not claim fully localized legal coverage.
- Preserve the system-language option and immediate SwiftUI locale update.
- Use SF Symbols consistently and localize labels/content descriptions.
- Verify Dynamic Type, VoiceOver, RTL, compact iPhone height and iPad width.
- Do not hard-code user-visible English in new Views.

## Release blockers

A derived release must not ship with template identity, example URLs, support email, demo product IDs, Google test ad IDs, placeholder legal text, placeholder icon references or the sample provider.

The paywall is app code, not a reusable marketing draft. A release must replace the shell's generic title, explanation and benefits in every shipped localization. Benefits must name only entitlements the selected monetization configuration and StoreKit product actually grant; the displayed price and period remain StoreKit-derived. When Settings opens the paywall, present it modally or otherwise ensure the navigation bar does not show both Back and Done for the same exit.

When execution is authorized, the release checks are:

- `scripts/validate-shell.sh --release`
- `xcodegen generate`
- Xcode Release build and unit tests before archive/upload

TestFlight requires an explicit manual workflow dispatch and the exact confirmation text. Its build number must be unique and monotonically safe relative to prior uploads; a UTC timestamp plus workflow run number is the shell default. Never upload or trigger a hosted run unless the user explicitly authorizes it.

The Welding Wallet bridge is product-specific and must follow the app repository’s current business model. Its production-logic option is `subscription`: three active cylinders remain free, a verified monthly subscription unlocks unlimited active cylinders, and the archive gate rejects advertising frameworks and metadata. Do not preserve an obsolete ad-enabled bridge after the derived app removes ads.


## Mandatory commerce-surface rule

Paywall, purchase, restore, subscription and win-back surfaces must contain no app logo, AppIcon, named image asset, custom brand mark or app-name hero. Generic SF Symbols may support comprehension, but they must not reproduce the app mark. This house rule is deliberately stricter than Apple's published in-app UI wording. When execution is authorized, run `scripts/check-commerce-branding.sh`; a failure blocks release. App Store promotional IAP and win-back media must separately follow Apple's rule that the promotional image cannot be the app icon or an app screenshot.

## Ad-free and advertising products

The default `Shell` target is physically ad-free: it does not link GoogleMobileAds/UMP and its `Info.plist` contains no GAD or SKAdNetwork metadata. Use it for free, purchase, subscription and usage-cap apps.

Only an intentionally ad-supported app uses `ShellAds`, `Info-Ads.plist`, and an advertising monetization mode. Use `scripts/validate-shell.sh --release-ads` for that profile. Never copy advertising metadata into the default plist.

## Compliance, localization, backup and migrations

- Treat `docs/APPLE_STORE_COMPLIANCE.md` as a release gate, not a guarantee. Re-open every official Apple source and mark each current numbered guideline subsection PASS or N/A with evidence.
- `gooduse-common-localization-v1.json` is the reviewed 31-locale shared terminology contract copied from the Android shell. It does not authorize advertising a locale until all app, legal, product and store text is complete.
- Backup is disabled by default and has no entitlement. Enable it only with an app-owned `NativeBackupProviding` implementation, reviewed privacy disclosures, versioned serialization and recoverable conflict handling. Decode untrusted backups into temporary state, validate IDs/references/values, enforce every current free or paid limit, and commit atomically only after all checks pass.
- Complete `docs/DERIVED_APP_RELEASE_WIRING.md` before every TestFlight production-logic build and storefront submission. Code, final archive, policies and App Store Connect metadata must describe the same product.
- Record the adopted `ShellContract.currentVersion`. A breaking adoption requires ordered, idempotent `ShellMigration` steps; never erase data or silently skip a missing step.
