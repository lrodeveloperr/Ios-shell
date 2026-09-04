# Native UI regression matrix

Run only when the user authorizes testing. Source tests live in `ShellUITests`; this checklist covers visual and policy-sensitive cases automation cannot prove.

| Destination | Size / mode | Required checks |
|---|---|---|
| Small iPhone | current compact supported iPhone, portrait | no clipping; every tab has a visible icon and label; onboarding fits; checkbox and legal links reachable; keyboard does not hide action; Settings opens without termination; paywall price/period/restore/legal visible |
| Large iPhone | portrait and landscape | readable line lengths; sheets dismiss; bottom navigation and optional banner do not overlap |
| iPad | compact and regular split/full screen | adaptive sidebar/tab behavior; no empty unusable column; sheets and forms remain bounded |
| Accessibility | largest accessibility Dynamic Type | scrolling preserves every action; labels do not truncate meaning; 44-point targets |
| VoiceOver | iPhone and iPad | logical order; icons have labels; purchase price/period and restore are announced |
| RTL | Arabic or Hebrew pseudolocalized build | navigation, chevrons, text alignment and directional icons mirror correctly |
| Localization | every advertised locale | no raw keys, accidental English, clipped price/period or untranslated legal/purchase text |
| Onboarding | first install and revised legal version | exactly one explicit acceptance gate; links readable before acceptance; re-consent triggers after version change |
| Commerce | one-time, subscription, cap exhausted, product unavailable, retry, pending, cancelled, grace, billing retry, expired, revoked, offline, restore | product-specific title/message/benefits match the actual paid unlock; localized StoreKit price/period; cancellation retains paid-through access; grace stays entitled; billing retry routes to management; no permanent spinner; no duplicate Back-and-Done controls; no app logo/icon/brand asset; no false unlock; recovery is clear |
| Settings | checking, never subscribed, active/renewing, cancelled-paid-through, grace, billing retry, expired, revoked, offline-valid | no placeholder rows; inactive states have no success tick or Manage action; active/recoverable states show truthful copy and state-appropriate icon; legal button titles/subtitles match neighboring row colors |
| Ads target | consent required/not required/error; remove-ads bought | no request before consent permits; privacy choices available; banner uses the SDK-reported adaptive height inside each destination content safe area; native tab bar remains fully visible below it; removed after verified entitlement |
| Legal links | onboarding, Settings and paywall | every control opens the configured current HTTPS document in the in-app browser; no copied placeholder body; all published destinations return success before release |
| Ad-free target | default `Shell` archive | no banner gap; no Google SDK linkage; no GAD/SKAdNetwork metadata |
| Backup option | disabled; native Files manual backup; provider-managed backup when explicitly required | no UI/capability when disabled; no account gate for manual Files backup; Create/Import progress, cancellation and failure are visible; replacement has a preview and destructive confirmation; malformed, oversized, foreign-app, duplicate-ID and broken-reference restores fail atomically; valid paid-era data is preserved without importing entitlement or unlocking over-limit operations; unsupported rollback/cloud-delete/history controls are absent |
| Backup + usage cap | `5 of 5`, `1 of 5`, `0 of 5`; older/current/newer backup; reinstall; replacement device | deleting data, reinstalling and importing older/empty/repeated backups never replenish usage; imported/restored history can raise but never lower the bounded high-water mark; fifth committed outcome succeeds; sixth attempt reaches the paywall; purchase state is unchanged by data import |
| Release-test isolation | Debug, Release UI test and archived Release | test reset/StoreKit fixtures are present only in Debug or a dedicated Release-test condition; each UI scenario has an isolated ledger namespace; Keychain tests use normal simulator signing; archived executable contains no reset/fixture path or unused Apple sign-in/iCloud capability |

Required automation destinations when execution is authorized:

- A compact supported iPhone simulator.
- A current large iPhone simulator.
- A current iPad simulator.
- English, Spanish and an RTL locale.
- Default and accessibility Dynamic Type sizes.
