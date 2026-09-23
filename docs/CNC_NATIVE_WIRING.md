# CNC Repeat Job Bench — native ledger integration

## Scope

This derived branch integrates the local `CNCRepeatJobEngine` v0.4.0 candidate into the Swift 6 / SwiftUI `ios-shell`. `Vendor/CNCRepeatJobEngine` contains the domain code and engine XCTest source. The app uses the original native `TabView`, `NavigationStack`, Settings, paywall, legal, localization and access composition. The product provider is `CNCFeatureProvider`.

| Tab | One job | Representative SF Symbol | Avoided repetition |
| --- | --- | --- | --- |
| Jobs | Select or start an exact approved job | `tray.full` | Only a status/count summary; no setup checklist or audit details. |
| Run | Execute the current gate, count, resolve holds | `gearshape.2` | Shows one primary action for the current state; rare changes, handoffs, attachments and closeout sit in **More run actions**. |
| Setups | Author, revise, inspect and approve references/policy | `wrench.adjustable` | Six reference values and dimensions live here, not on Jobs. |
| Records | View historical outcomes, export/backup/archive | `doc.text` | Full counts and reviews live in a record detail, not repeated on the list. |

The app icon is the 1024-pixel engine asset: a spindle/cycle symbol. Tab icons are native SF Symbols in one `Label` each; the tab label describes the job, and the symbol describes its object or action. Settings stays in the shell toolbar. The native UI is the selected white/inset-grouped design, with blue action tint and a light appearance. The earlier HTML Site is a visual guide, not compiled iOS output.

## Engine boundary

`BenchAppModel` places the actor repository in Application Support, keeps the operator's self-entered name in app-only defaults, and routes every production mutation through `BenchStoreKit.apply` with verified StoreKit access checked at commit. No paid flag is saved in the shop database. PDF, CSV and JSON exports use a protected temporary file and native `ShareLink`; backups, archives, and archive restore use engine validation. A record receipt is not itself an archive file.

The shell adds a generic `.freemiumSubscription` profile: product content stays visible while the engine enforces the first two distinct part-and-machine families. Shell purchase UI displays the two configured monthly/annual StoreKit products and prices. The engine remains the authority for whether a specific approval or run start is allowed. Existing runs, history, safety revisions and export remain available after a lapse.

## Product Design source review

- **Removed:** repeated approved setup rows from Jobs and repeated full counts from tab lists. Setup detail sits in Setups; production counts sit in Run; historical counts sit in Records detail.
- **Kept:** a brief active-job count in Jobs because it helps select the right run; the more detailed count belongs in Run.
- **Recovery:** mismatched preparation has correction plus explicit issue resolution; rejected inspection has a new review cycle; pending handoff exposes named acknowledgement/reassignment; count correction is available before closeout.
- **Icon check:** existing `tray.full` and `doc.text` are already used by the shell; `gearshape.2` represents machine operation and `wrench.adjustable` setup work. Every tab remains a single native SF Symbol `Label`, with accessibility supplied by its text label. Verify icon rendering on iPhone and iPad in Xcode UI tests.
- **Evidence limit:** the private Site required ChatGPT sign-in in the cloud design browser. This is a source/flow review of the selected layout and SwiftUI code, not a completed screenshot-based perceptual audit.

## Remaining gates before release

- Run `xcodegen generate`, a Swift 6/Xcode build, engine tests, shell XCTest and UI tests on a Mac. This environment has no Swift or Xcode. The existing validation script reaches branding and one-locale localization checks here, then stops at the missing macOS `plutil` tool. A successful release gate is not claimed.
- Replace `support@example.com` and both `example.com` legal URLs with reviewed, published destinations. Verify those pages and the privacy manifest against the final backup/export and StoreKit behavior.
- Create both auto-renewable subscription products in the same App Store Connect group, assign reference US prices $4.99/month and $39.99/year there, then test purchase/restore/grace/expiry/revocation offline and online. The UI always reads displayed prices from StoreKit.
- Test on the intended small iPhone, iPad, VoiceOver and Dynamic Type. Verify every tab icon displays, all four destinations remain distinct, forms handle keyboard/safe areas, and hold recovery cannot be bypassed.
- Observe real operators; the contract's shop profile and cadence remain provisional.
