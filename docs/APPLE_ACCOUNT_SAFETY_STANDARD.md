# Apple account safety standard

Purpose: make Apple compliance part of normal delivery rather than a separate emergency exercise.

This standard reduces developer-account enforcement risk. It does not promise that an account can be made literally "ban-proof"; Apple retains review discretion and policies change.

## Operating principle

Be consistent. Be transparent. Keep evidence. Never try to game App Review.

An ordinary App Review rejection is a normal quality/compliance event:
1. read the exact rejection;
2. reproduce and understand it;
3. fix the underlying issue or provide accurate evidence;
4. update metadata/review notes if needed;
5. resubmit.

Never respond to a rejection by hiding functionality, changing behavior only for Review, rotating accounts, creating shadow developer accounts, or otherwise circumventing the decision.

## Account-level red lines

The following are release blockers and escalation items:

- hidden, dormant, reviewer-detection, or post-review-switched functionality;
- bought/fabricated ratings, reviews, installs, rankings, or misleading acquisition practices;
- materially misleading metadata, screenshots, pricing, trial, subscription, privacy, or capability claims;
- unauthorized IP, copied branding, impersonation, or deceptive affiliation;
- bypassing StoreKit for digital goods where Apple requires IAP;
- knowingly false privacy disclosures or privacy manifests;
- submission from an identity, entity, banking, tax, or ownership configuration that is inconsistent or cannot be documented;
- sharing Account Holder credentials, 2FA codes, signing credentials, or unrestricted API keys with contractors;
- use of another developer account to route around an Apple enforcement action;
- repeatedly resubmitting a known violation without fixing or substantively addressing it.

## Reviewer/user parity

The reviewer must receive the same material application behavior a real user receives.

- No reviewer-specific code paths.
- No hidden remote flags that materially change app purpose after approval.
- Declare demo/sample data, test accounts, hardware requirements, region restrictions, feature flags, and unusual flows in App Review notes.
- If a remote service controls a feature, record the release-time configuration used during review.
- If functionality cannot be reviewed without special access, supply reproducible access.

## Distinct-app / 4.3 control

Portfolio scale is permitted only when products remain genuinely distinct.

Before submission record:
- the app's unique customer problem;
- unique engine/domain logic or materially different workflow;
- why this is not a reskin or duplicate of another portfolio app;
- any shared shell/components used;
- store metadata and screenshots specific to this app.

A 4.3 rejection is handled by fixing, consolidating, or explaining the product distinction. It is not a reason to evade review.

## Access and associated-account hygiene

- One verified business identity; keep legal name, address, D-U-N-S, tax, banking and Account Holder information consistent.
- Use individual App Store Connect users/roles and revocable API keys.
- Apply least privilege. Contractors get only the permissions needed for the task.
- Never share the Account Holder password or 2FA code.
- Remove stale users and revoke unused API keys/certificates.
- Do not create backup/shadow Apple Developer accounts as an enforcement workaround.
- Treat contractor conduct, SDK behavior and automated submission activity as your responsibility.

## Automation rules

Preferred order:
1. official App Store Connect API;
2. supported Fastlane actions using official Apple interfaces;
3. manual App Store Connect.

Do not build automation intended to conceal activity, bypass Apple rate limits/security, scrape protected account surfaces, fake review state, or manipulate rankings/reviews.

Every automated release must leave an auditable record: commit SHA, workflow run, build number, bundle ID, App Store version, metadata revision and submitter.

## Release evidence bundle

For every App Review submission retain:
- source commit SHA/tag;
- build number and version;
- bundle ID and App Store Connect app ID;
- archive/IPA identity when available;
- exact metadata and localization submitted;
- screenshots/previews submitted;
- App Review notes;
- privacy answers and privacy-manifest/SDK inventory;
- IAP/subscription product IDs and business model;
- feature-flag / remote-config state relevant to review;
- legal/privacy URLs and effective versions;
- reviewer credentials/sample-data instructions where applicable;
- CI/workflow run;
- rejection/resolution correspondence, if any.

Do not store secrets in the evidence bundle.

## Submission gate

A release is blocked unless all are true:

- [ ] App does what its listing says.
- [ ] Reviewer and normal-user behavior materially match.
- [ ] Product is distinct enough to defend under Guideline 4.3.
- [ ] Privacy labels, privacy manifest, SDKs and actual code agree.
- [ ] IAP/subscription implementation and listing agree.
- [ ] Screenshots and metadata match the submitted build.
- [ ] IP/brand provenance is documented.
- [ ] No hidden/debug/demo/reviewer-only functionality ships.
- [ ] Identity, tax, banking and developer-account details remain consistent.
- [ ] Official/supported submission interfaces are used.
- [ ] Release evidence bundle is saved.

## Rejection response protocol

Treat rejection as actionable feedback, not as an account crisis.

1. Preserve the rejected build and Apple message.
2. Identify the exact guideline and affected behavior/metadata.
3. Decide: fix, clarify with evidence, or appeal.
4. Make the smallest honest correction that resolves the actual issue.
5. Update screenshots/metadata/privacy/review notes if the fix changes them.
6. Re-run the normal release gate.
7. Respond professionally and specifically; do not argue about unrelated issues.
8. Resubmit.
9. Record the outcome and add any reusable lesson to the shell/release checklist.

Escalate internally if Apple mentions fraud, deception, account association, manipulation, repeated misconduct, termination, or Developer Program agreement breach.

## Monthly account hygiene

- Review App Store Connect users/roles.
- Revoke stale API keys/certificates/profiles.
- Confirm Account Holder recovery methods and 2FA.
- Confirm legal entity, banking and tax details remain current.
- Review active SDKs and privacy declarations.
- Review any unresolved App Review messages.

## Quarterly policy review

Re-read the current:
- App Review Guidelines;
- Apple Developer Program License Agreement;
- App Store Connect terms/help relevant to payments, subscriptions, privacy and account access;
- third-party SDK/privacy requirements.

Update the canonical shell gate when Apple changes a rule.

## Incident response

If Apple threatens suspension/termination or removes multiple apps:
- stop non-essential submissions;
- preserve all Apple correspondence and release evidence;
- identify whether the issue is app-specific or account-level;
- revoke suspicious/stale third-party access;
- verify no credentials were compromised;
- prepare a factual timeline and evidence package;
- fix confirmed violations before appealing;
- use Apple's formal appeal/contact route;
- do not create or use another developer account to work around enforcement.

Revenue continuity must rely on legitimate diversification (web, Android, other marketplaces) and source/data backups, not enforcement evasion.
