# Native backup and usage-integrity guide

Use this guide whenever a derived app offers user-controlled backup and also has a free-use limit, one-time unlock or subscription. Backup, usage metering and StoreKit are separate trust domains. A restore may replace user data, but it must never manufacture free usage or paid access.

## 1. Choose the smallest truthful backup architecture

For a local-first app whose users only need to save and restore on demand, prefer native Files export/import:

- Export a versioned `FileDocument` with SwiftUI `fileExporter`.
- Import with SwiftUI `fileImporter` and correctly bracket access to its security-scoped URL.
- Let the user choose iCloud Drive, On My iPhone/iPad or another Files provider. The app does not need an account, Sign in with Apple or an iCloud-container entitlement for this flow.
- Keep backup controls in Settings and available without authentication.

Add automatic cloud history, account identity or an app-owned iCloud container only when the product requirement genuinely needs them. Do not add Sign in with Apple merely to name, gate or transport a manual backup.

The bundled `NativeBackupProviding`/`BackupSettingsView` pair is a disabled provider-managed seam, not a finished user-selected Files implementation. Do not enable it unchanged and claim Files backup. When manual Files backup is selected, make the reusable upstream screen own the native exporter/importer presentation and keep app code limited to serialization, validation, preview and atomic commit.

Do not expose controls the implementation cannot make dependable. A backup list, cloud-delete action, merge choice or “Roll back last restore” action must not exist unless the app persists the corresponding state, handles failure and has end-to-end tests for it. For the common replace-only design, use two clear actions: **Create Backup** and **Import Backup**.

## 2. Backup file contract

The product owns the schema. Use a deterministic envelope with, at minimum:

- app identifier;
- schema version;
- export timestamp;
- product records and settings that are intentionally portable; and
- the bounded free-usage high-water mark when the app has a usage cap.

Never export or import:

- StoreKit transactions, receipts, cached entitlement objects or a paid-access Boolean;
- Keychain secrets, authentication credentials or signing material;
- active timers, in-flight commits or drafts whose invariants cannot be restored safely; or
- a rollback snapshot as ordinary customer data.

Use a product-specific uniform type identifier conforming to JSON when the payload is JSON. Give files a stable, portable name. Set a product-appropriate byte limit and reject oversized input before loading the complete file into memory. If a plain backup is not app-encrypted, state that accurately in the UI and privacy documentation; the user controls where the Files document is stored.

## 3. Import is an untrusted transaction

Treat every imported file as hostile or stale:

1. Confirm that the selected URL is a regular file and obtain security-scoped access when required.
2. Check the file size before reading it. Stop security-scoped access on every exit path.
3. Decode into temporary memory. Do not mutate live storage while decoding.
4. Validate the app identifier, supported schema range, exact required fields, optional-field allowlist, IDs, uniqueness, references, enum values, number bounds and dates.
5. Migrate supported older schemas in temporary memory and validate the migrated result again.
6. Build a restore preview showing the export date, record counts and the post-restore free-use result.
7. Require explicit confirmation immediately before a replace operation. Use destructive styling for the confirming replacement action, not for the ordinary navigation row that opens the preview.
8. Re-check that no conflicting domain operation is active.
9. Commit the complete target state atomically. Preserve the currently verified entitlement and clear nonportable active sessions/drafts.
10. Reconcile the usage ledger only as part of the successful restore transaction. On any failure, leave all local data and metering state unchanged.

Never report success when the exporter is merely presented or the importer is merely selected. Report export success only from the exporter completion callback, and distinguish cancellation from failure.

## 4. Five-free-use and backup invariant

Define exactly what consumes one free use before implementation. Count only a successfully committed domain outcome, never a button tap, form opening, validation attempt, cancelled run or retry. Give each successful outcome a stable ID of no more than 128 UTF-8 bytes and make re-recording the same ID idempotent.

For a limit `L`, maintain a durable device ledger with a bounded count and the stable IDs available on that device. For a restore, calculate:

```text
restoredUsage = min(L, max(deviceUsage, importedUsage, restoredCompletedOutcomeCount))
```

The result can stay the same or increase; it can never decrease. Therefore:

- deleting local records does not replenish free uses;
- reinstalling on the same device does not replenish free uses;
- importing an older or empty backup does not replenish free uses;
- importing the same backup repeatedly does not consume or grant uses;
- moving to a new device carries the high-water mark through the customer-owned backup; and
- an imported value above the configured limit is rejected or safely capped according to the versioned schema, never trusted as arbitrary state.

Use a device-only Keychain accessibility class, such as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, for the production ledger. This keeps it available after first unlock, prevents migration as a Keychain secret and normally survives app reinstall on the same device. The portable high-water mark belongs in the backup because device-only Keychain data does not move to a replacement device.

Keychain loading must distinguish `errSecItemNotFound` from corruption, decoding failure and access errors. Only “not found” means a new ledger. Any other durable-ledger failure must fail closed for another free start, preserve the highest known in-memory/compatibility value and offer a recoverable retry path. Never convert an unreadable ledger into zero free uses consumed.

## 5. StoreKit remains authoritative

Backup restores customer data; StoreKit restores purchases. Keep these paths separate:

- Paid access comes only from verified current StoreKit entitlement state.
- `AppStore.sync()` is a visible, user-initiated Restore Purchases action, not part of data import.
- A backup may not unlock Pro, extend an expiry, change a product ID or restore a subscription.
- Importing paid-era data must not silently delete it. Preserve it as viewable/exportable or locked/read-only when the product can represent that safely, then apply the current entitlement and quota rules to new paid operations.
- A lapse, reinstall or data restore must not erase the customer’s records.

## 6. Settings and interaction contract

The default local-first presentation is:

- **Create Backup** — opens the native Files exporter and shows progress while data is prepared.
- **Import Backup** — opens the native Files importer, validates the file, shows a preview and asks for replacement confirmation.
- concise explanatory copy stating that the user chooses the storage location and that purchase status is not part of the backup.

Disable duplicate actions while work is active. Keep buttons at least 44 points, make the complete visible row tappable, localize every status/error string and preserve VoiceOver, Dynamic Type, RTL, compact-height and iPad behavior. An error must identify the failed stage without exposing raw payloads or secrets. A restore must never route through onboarding or an authentication screen.

## 7. Required automated evidence

Unit-test at least:

- valid round-trip and stable filename;
- empty, malformed, foreign-app, unsupported-version and oversized files;
- duplicate IDs, broken references, invalid enums/numbers and unknown fields;
- legacy migration followed by validation;
- atomic failure with byte-for-byte equivalent live state;
- active-operation restore rejection;
- entitlement preservation and attempted entitlement injection;
- current/imported/restored-count high-water combinations;
- exact fifth-use success and sixth-use paywall;
- duplicate completion, deletion, reinstall/preference reset and older-backup cases;
- Keychain not-found, corruption, access failure, save failure and retry recovery; and
- StoreKit purchase restoration independent from data restoration.

UI-test at least:

- backup controls require no sign-in and remain reachable on compact iPhone and iPad;
- exporter completion, cancellation and failure states;
- importer cancellation, invalid-file error, preview and destructive replace confirmation;
- no cloud-delete, sign-out or rollback control when those features do not exist;
- `5 of 5`, `1 of 5` and `0 of 5` presentation; and
- the sixth committed-use attempt reaches the truthful StoreKit paywall without changing local data.

## 8. Release-test and archive isolation

Run the upload gate in this order: static/source checks, Release compilation, Release unit/UI tests, credential/app-record verification, archive, distribution-signing verification, App Store validation, upload and exact IPA retention. A failed test must prevent credentials, archive and upload steps from running.

When Release UI tests need reset, unavailable-product or Pro fixtures:

- compile them behind a dedicated condition such as `RELEASE_UI_TESTING` (often `#if DEBUG || RELEASE_UI_TESTING`);
- pass that condition only to the simulator test command;
- never include it in the archive command or production workflow configuration;
- give each UI test a unique test-only ledger namespace instead of deleting production-style Keychain records; and
- allow normal ad-hoc simulator signing for a test that exercises Keychain. `CODE_SIGNING_ALLOWED=NO` invalidates that integration test.

Before upload, inspect the signed executable and embedded profile—not only source settings. Assert the exact bundle/team identifiers, distribution profile, `get-task-allow=false`, expected capabilities and absence of unused Sign in with Apple or iCloud entitlements. Validate the IPA with App Store Connect before upload and retain its digest for traceability.

## 9. Release decision checklist

- [ ] The backup architecture is the smallest one the product needs; manual Files backup has no artificial login gate.
- [ ] Create and Import actions have real completion, cancellation, progress and failure behavior.
- [ ] Restore validates before mutation, previews consequences and commits atomically.
- [ ] StoreKit entitlement is absent from the backup and preserved from the current verified device state.
- [ ] The free-use ledger is monotonic across deletion, reinstall and restore.
- [ ] A replacement device receives the bounded high-water mark through the backup.
- [ ] Unsupported rollback, merge, cloud-delete and backup-history controls are absent.
- [ ] Policies and store metadata describe the actual portable fields, protection and deletion behavior.
- [ ] Release tests exercise signed Keychain behavior and all fixtures are excluded from the archive.
- [ ] The signed IPA contains only required capabilities and passes App Store validation before upload.

## Official Apple references

- [SwiftUI fileExporter](https://developer.apple.com/documentation/swiftui/view/fileexporter%28ispresented%3Adocument%3Acontenttype%3Adefaultfilename%3Aoncompletion%3A%29-32vwk)
- [SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29)
- [Restricting Keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
- [StoreKit current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- [StoreKit AppStore.sync](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)
