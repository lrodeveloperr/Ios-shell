# iOS 18 shell audit — 2026-09-28

This audit reviews the reusable shell as a system rather than only the visible navigation. Scope includes composition, navigation, state restoration, onboarding, settings, commerce, access control, usage limits, advertising/privacy, localization/RTL, backup/restore, legal presentation, launch resources, accessibility gates, tests, validation and release documentation.

The audit is based on the current populated repository `lrodeveloperr/Ios-shell`. The separate `ios-18-shell` repository contained only a minimal README at audit time and was not treated as the implementation source.

## Current platform references

- Apple SwiftUI `sidebarAdaptable`: https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable
- Apple SwiftUI `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview
- Apple SwiftUI state restoration / `SceneStorage`: https://developer.apple.com/documentation/SwiftUI/restoring-your-app-s-state-with-swiftui
- Apple auto-renewable subscriptions: https://developer.apple.com/app-store/subscriptions/
- Apple launch-screen configuration: https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- Google UMP for iOS: https://developers.google.com/admob/ios/privacy
- Google adaptive banners for iOS: https://developers.google.com/admob/ios/banner

## Audit result

| Area | Result | Audit conclusion / correction |
|---|---|---|
| App entry point | PASS | Native Swift 6 / SwiftUI app lifecycle remains appropriate. |
| Top-level tabs | CHANGED | Moved to the iOS 18 `Tab(value:content:label:)` API with `.sidebarAdaptable`. |
| Top-level selection | CHANGED | Added `@SceneStorage` so each scene returns to its last destination. Invalid/stale destination IDs normalize safely. |
| Single-destination navigation | PASS / HARDENED | Shell continues to supply native stack navigation without forcing a tab bar. |
| List-detail navigation | CHANGED | Removed the manual 700-point `GeometryReader` split. Added optional `makeSplitCanvas` and a shell-owned `NavigationSplitView` with stable selection. |
| iPhone/iPad adaptation | CHANGED | Compact behavior now comes from native navigation collapse instead of device/width thresholds. |
| Feature boundary | PASS / EXTENDED | Existing `makeCanvas` providers remain valid. The split contract is additive and optional. |
| Access gate | PASS | Feature code is still not composed until `AccessController` grants access. |
| Usage metering | PASS | Stable IDs, deduplication, bounded keychain persistence and post-success recording remain correct. |
| StoreKit verification | PASS | Verified transactions, current entitlements, updates, revocation/expiry, restore and offline expiry remain authoritative. |
| Subscription sign-up | CHANGED | Removed direct purchase from shell upgrade actions. The commerce surface now shows the live StoreKit name, full renewal price, billing period and benefit before Subscribe invokes Apple confirmation. |
| One-time purchase sign-up | PASS / HARDENED | Still uses live StoreKit product name/price; unavailable product state now explains the failure and exposes retry. |
| Restore purchases | PASS | Remains an explicit user action; no automatic `AppStore.sync()`. |
| Subscription management | PASS | Billing retry routes to Apple management; Settings exposes management only for relevant verified states. |
| Commerce modal ownership | CHANGED | Settings opens its own paywall sheet rather than requesting a second root-level modal over the Settings sheet. |
| Onboarding | CHANGED | Uses the native iOS checkbox toggle style; guided tour can be skipped to the final acceptance page without bypassing required legal acceptance. |
| Legal documents | PASS / HARDENED | Published HTTPS source of truth remains in `SFSafariViewController`; unnecessary safe-area overrides were removed. |
| Settings | HARDENED | Safer mailto construction, plain row button styling, immediate locale-resolved navigation titles and localized system-language copy. |
| In-app language switching | CHANGED | System-language formatting now preserves region/script only when that language is actually supported; otherwise it falls back to the shipped language instead of producing mismatched direction/content. |
| RTL | CHANGED | Direction uses Foundation's language character direction instead of a manually maintained RTL-language list. |
| Localizations | PASS / EXTENDED | English/Spanish key parity retained; all newly exposed interaction states are localized. |
| Ads target separation | PASS | Default target remains physically ad-free; ad SDK stays isolated behind `ADS_ENABLED`. |
| UMP consent | CHANGED | After a consent-update error, the shell rechecks UMP's `canRequestAds` so a still-valid previous-session decision is respected, while never requesting ads unless UMP permits it. |
| Adaptive banner | PASS | Existing large anchored adaptive banner uses the SDK-reported width/height and a safe-area inset. |
| Backup seam | PASS / HARDENED | Remains disabled by default and app-owned. Operations are now single-flight; a missing provider fails loudly instead of silently succeeding. |
| Destructive restore | CHANGED | Replacing device data now requires an explicit destructive confirmation. |
| Launch screen | CHANGED | Removed the accent-color splash and returned to a neutral launch screen that more closely matches normal first-screen system backgrounds. |
| Privacy manifest | PASS | App-only UserDefaults required-reason declaration remains present; derived apps must reassess when adding APIs/SDK behavior. |
| App icons / tint | PASS AS TEMPLATE | Template assets remain placeholders by design and are release-blocked until a derived app replaces them. |
| Configuration placeholders | PASS AS TEMPLATE | Example identity, URLs, product IDs and support address remain deliberate template values and are rejected by release validation. |
| Shell Lab | PASS / UPDATED | Debug-only; responsive description now reflects native `NavigationSplitView` rather than a 700-point breakpoint. |
| Unit tests | EXTENDED | Added supported-locale fallback and optional split-provider contract coverage. |
| UI tests | EXTENDED | Subscription test now checks the transparent offer step; navigation test checks the list-detail path. |
| iPad CI coverage | CHANGED | Manual CI now includes a dedicated iPad adaptive-navigation regression. |
| Validation script | CHANGED | Enforces iOS 18 tabs, split navigation, scene restoration, transparent subscription terms, backup confirmation and iPad regression. Cross-platform scan now falls back to stock `grep` when `rg` is unavailable. |
| Release docs | CHANGED | Removed stale rules requiring direct subscription purchase and legacy `.tabItem` implementation. |

## Intentionally not automated by the reusable shell

The reusable shell cannot prove derived-app legal accuracy, product-specific privacy declarations, linguistic review, app-specific backup integrity, App Store Connect product configuration, production advertising identifiers, App Review metadata or real-device visual quality. Those remain release gates for each derived app.

Likewise, the shell deliberately does not infer feature-specific list/detail structure. A conventional feature can keep `makeCanvas`; a real list-detail feature opts into `makeSplitCanvas` and supplies stable selection IDs while the shell owns the native navigation container.

## Execution status

Source and contract corrections were made on the audit branch. The manual GitHub Actions workflow was **not dispatched** during this audit because repository policy requires explicit authorization before consuming hosted macOS execution or triggering release-related workflows. The branch adds/updates the tests that should run when that workflow is deliberately authorized.
