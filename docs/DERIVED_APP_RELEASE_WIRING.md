# Derived-app release wiring checklist

Use this checklist for every app created from the shell. It records the failure modes found during the Welding Gas Wallet production-test audit and the upstream correction that prevents recurrence. A checked box requires evidence from the derived source, final archive, App Store Connect, or a device test.

## Regression map

| Failure mode | Root cause | Upstream correction | Required derived-app evidence |
|---|---|---|---|
| Blank custom tab icon | A custom drawing was placed directly in `tabItem`; the native iPhone bar discarded it | Tab items must use one native `Label` with an SF Symbol or template asset | UI test confirms every visible tab button contains an image |
| Settings crashes on presentation | A required observable environment value was not injected across the sheet boundary | Root sheets re-inject model, language and locale; Settings receives its model explicitly | Open and dismiss Settings on compact iPhone and iPad |
| Banner collides with the tab bar | The ad safe-area was applied outside the destination or forced to a guessed height | Each destination owns a bottom safe-area slot sized from the Mobile Ads SDK | Test consent states and rotation with the native tab bar fully visible |
| Generic purchase draft ships | Template title, benefits or store name were treated as final product copy | Release checks reject known placeholders; the purchase action, errors and retry state are localized | Paywall names exact paid benefits and shows StoreKit price/period |
| Product load failure spins forever | The empty product state was rendered as loading even after the request ended | Paywall distinguishes loading from unavailable and provides a retry action | Test offline/failure, retry, pending, cancel, restore and success |
| Unsupported/stale locale persists | Stored selections and device language mappings were not checked against the current shipped list | `LanguageController` rejects stale values and resolves only enabled locales | Relaunch with a removed locale and test unmatched device languages |
| Partly translated locale is advertised | Shared shell terms were mistaken for a complete app translation | Exact key parity, duplicate-key rejection and the cultural checklist gate every enabled locale | Product, validation, notification, accessibility and commerce copy reviewed |
| Backup bypasses a free/paid limit | Imported data was trusted and committed without applying current domain constraints | Backup-provider contract requires temporary decode, integrity validation, limit enforcement and atomic commit | Malformed, duplicate-ID, broken-reference and over-limit imports fail without mutation |
| Test ads leak into a storefront binary | Demo IDs were stored as ordinary release configuration | Demo IDs are allowed only through an explicitly named internal test workflow and must be asserted in that archive | Storefront release gate rejects Google demo IDs; production-test archive identifies exact demo IDs |
| Upload build number is rejected | `GITHUB_RUN_NUMBER` can be lower than a previously uploaded timestamp build | Upload workflows use a UTC timestamp plus run number | Final archive `CFBundleVersion` is unique and greater than prior uploads |
| Hosted validation cannot start | The validator's executable bit was lost while publishing a content update | The shell tracks the executable mode and self-checks it | Fresh GitHub checkout executes `scripts/validate-shell.sh` directly |
| Release unit tests cannot import the app | The Release module was built without testability while tests used `@testable import` | Upload workflows enable testability only for the simulator test command | Release unit tests compile and pass before the unaffected archive step |
| Export-compliance prompt repeats | The final archive lacked a code-grounded encryption declaration | Both plist profiles carry `ITSAppUsesNonExemptEncryption`; archive verification checks it | Reassess the value whenever networking or cryptography changes |
| App Store text contradicts the binary | Review notes, screenshots or product metadata described an older business model | Storefront and subscription metadata are a required parity gate | Review notes accurately describe ads, consent, limits, subscription and test path |

## Code and archive

- [ ] The selected monetization mode matches the product: free access, limit behavior, ads and the paid unlock are tested as one contract.
- [ ] Every mutation path enforces the same entitlement or domain limit, including add, duplicate, import, restore, migration, deep link and background processing.
- [ ] StoreKit product IDs and types exactly match App Store Connect. Customer price and billing period come only from `Product`.
- [ ] Pending, cancelled, unverified, expired, refunded and revoked transactions do not unlock access.
- [ ] A failed product request leaves a localized retry action rather than a permanent spinner.
- [ ] The archive contains the intended bundle ID, build number, plist profile, product configuration and advertising IDs.
- [ ] `ITSAppUsesNonExemptEncryption` is verified in the archive and is still truthful for the derived code.
- [ ] Unit tests run in the upload workflow before signing and upload.

## Advertising

- [ ] An internal production-logic test may use only Google's official demo app and banner IDs and is clearly excluded from App Review.
- [ ] A storefront ad build uses publisher-owned IDs and the ad release validator; a non-ad build contains no Mobile Ads framework or metadata.
- [ ] UMP finishes before an ad request. Privacy choices remain reachable afterward.
- [ ] The adaptive banner uses the SDK height inside destination content and never overlaps the native tab bar, controls or scroll content.
- [ ] A verified remove-ads entitlement or subscription removes the banner immediately.

## Localization and culture

- [ ] `supportedLanguages` contains only complete, reviewed catalogs; a removed or corrupt stored selection falls back safely.
- [ ] Tab titles, filters, validation, backup errors, StoreKit states, notifications, search synonyms and accessibility labels use localization keys.
- [ ] Dates, decimal input, units and money use the selected locale; persisted values remain canonical.
- [ ] Terminology is natural for the target trade and region, not merely literal. Spanish variants, gas names, cylinder/bottle terminology and measurement conventions receive regional review.
- [ ] Text expansion, compact height, Dynamic Type, VoiceOver and RTL behavior pass on real layouts.
- [ ] Legal-document language is disclosed when a matching localized policy is unavailable.

## Store and policy parity

- [ ] Every policy/support/deletion/safety URL returns the intended current document over HTTPS.
- [ ] App description, promotional text, keywords, screenshots, privacy answers and review notes use the correct locale and describe the current binary.
- [ ] Subscription duration, reference price, regional prices, availability, display names and descriptions match the in-app offer.
- [ ] Review notes state the real advertising SDK and consent flow, free limit, subscription benefit and reviewer test instructions.
- [ ] An internal test-ad build is never attached to an App Store review submission.

## Release decision

- [ ] Run the appropriate shell and localization validators.
- [ ] Build and run unit/UI tests on the intended Release configuration.
- [ ] Record the commit, archive build number, enabled locales, App Store product ID and test-ad/storefront profile.
- [ ] Stop the release if any code, archive, policy or App Store Connect claim disagrees with another.
