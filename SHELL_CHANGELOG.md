# Shell contract changelog

## Unreleased

- Passed the shell model explicitly into Settings and re-injected shell environment values at every root sheet boundary, preventing missing-environment crashes.
- Required native `Label` tab items, documented why custom `Canvas`/`Shape` content disappears from iPhone tab bars, and added focused Settings and tab-icon UI regressions.

## 2.0.0 — 2026-09-02

- Made the default target physically ad-free; added the opt-in `ShellAds` target.
- Prohibited app logo/icon/brand assets on all commerce surfaces and added a source guard.
- Added the official Apple compliance gate and native UI regression matrix.
- Added a 31-locale shared terminology baseline without claiming untranslated product support.
- Added disabled-by-default native backup interfaces and explicit restore-conflict choices.
- Added versioned shell migration infrastructure.

Breaking adoption note: derived ad-supported apps must select `ShellAds`; all other apps use `Shell`. Review `MIGRATIONS.md` before adoption.
