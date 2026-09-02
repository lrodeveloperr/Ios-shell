# iOS Shell

A native, reusable SwiftUI application shell for iPhone and iPad. It deliberately contains no product-domain logic.

## What is included

- SwiftUI and Apple system controls, iOS 18+, Dynamic Type, VoiceOver-friendly labels, light/dark mode
- `TabView` with the official `sidebarAdaptable` style: tab bar on iPhone, sidebar on iPad and larger windows
- Single-destination mode without unnecessary tabs
- Onboarding, placeholder legal pages, Settings, language, help, paywall, StoreKit 2 restore, and shell lab
- Populated, empty, loading, error, compact, expanded, advertising, and entitlement states
- Google Mobile Ads anchored adaptive test banner reserved with a safe-area inset
- English and Spanish starter localization
- CI for simulator builds/tests and a guarded cloud-signing TestFlight workflow

## Start a derived app

1. Edit `ShellConfiguration.swift` and `project.yml` for identity, destinations, links, products, and monetization.
2. Replace the placeholder feature area—not the adaptive shell.
3. Replace Google’s demo AdMob identifiers and implement consent before requesting production ads.
4. Configure matching products in App Store Connect. Keep StoreKit verification and restore behavior.
5. Replace the legal placeholders with reviewed, app-specific documents.
6. Run `xcodegen generate`, then open `Shell.xcodeproj`.

The shell removes repetitive UI decisions; it does not force every product into the same information architecture. One top-level task uses no tab bar. Two to five destinations use adaptive tabs/sidebar. List-detail content splits only when the available window makes that useful.

All advertising identifiers committed here are Google’s test identifiers. Never ship them as a production configuration.
