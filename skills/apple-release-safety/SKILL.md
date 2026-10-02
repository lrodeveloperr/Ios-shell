# Apple Release Safety Skill

Use this skill for any Apple submission, listing, TestFlight-to-review handoff, App Review rejection, or release automation task.

## Required behavior

1. Read `docs/APPLE_ACCOUNT_SAFETY_STANDARD.md`.
2. Read `docs/APPLE_STORE_COMPLIANCE.md` when present.
3. Treat ordinary App Review rejection as a fix/respond/resubmit workflow, not an account-ban event.
4. Never hide functionality, create reviewer-only behavior, manipulate reviews/rankings, or advise using another developer account to bypass enforcement.
5. Before submitting, verify:
   - binary/listing/reviewer-note parity;
   - privacy manifest + SDK + App Privacy parity;
   - IAP/subscription parity;
   - distinct-app/Guideline 4.3 rationale;
   - no debug/demo/reviewer-specific behavior;
   - official/supported App Store Connect submission interface;
   - release evidence bundle prepared.
6. If the user asks to submit despite a failed red-line check, block the submission and identify the exact failed control.
7. Preserve rejection messages and build evidence, fix the actual issue, then resubmit.
8. Escalate any Apple message alleging fraud, deception, manipulation, associated-account misconduct, or termination.

## Output discipline

For routine compliant releases, keep the process low-friction: run the checks, fix what is fixable, and proceed. Do not turn ordinary App Review feedback into unnecessary alarm.
