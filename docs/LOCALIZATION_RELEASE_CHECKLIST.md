# Localization release checklist

Do not expose a locale until every item is checked for the derived app. Key parity is necessary, but it is not cultural review.

## Catalog and behavior

- [ ] The locale has a matching `.lproj/Localizable.strings` file and exact English key parity.
- [ ] Product screens, empty/error/loading states, validation messages, notifications, accessibility labels and purchase/restore surfaces contain no fallback English.
- [ ] Stored enum values, activity records and canonical data are presented through localized display keys without changing their persistence format.
- [ ] Singular, plural and zero forms read naturally; sentences are not assembled from English fragments.
- [ ] Decimal input accepts the locale separator. Quantities, money, dates, times and currency names use the selected app locale.
- [ ] Search recognizes the words users see in the localized interface.
- [ ] App Store price and billing period come from StoreKit and remain grammatically correct together.

## Cultural and domain review

- [ ] A reviewer familiar with the target region approves product terminology, tone, formality and action labels in context.
- [ ] Units, cylinder/gas terminology, ownership/rental language and safety wording match normal regional trade usage.
- [ ] Domain states are translated by meaning in context, not by copying the source adjective. For example, “low” may describe remaining gas rather than physical height; validate the natural local trade expression.
- [ ] Benefit lists have correct grammatical agreement, and purchase buttons name the concrete entitlement or action instead of a vague abstraction such as “unlock control.”
- [ ] Destructive confirmations use an understandable local word and do not require typing an unexplained English token.
- [ ] Text avoids idioms, stereotypes, flags as language symbols and region-inappropriate examples.
- [ ] Support, privacy, terms, deletion and safety destinations are live and their available language is represented honestly.

## Visual and accessible QA

- [ ] Every screen is checked at large Dynamic Type with longer translated text and no clipping, overlap or hidden controls.
- [ ] VoiceOver reads controls, values and status changes naturally in the target language.
- [ ] Compact iPhone and iPad layouts are checked in portrait and landscape where supported.
- [ ] RTL locales receive an RTL pass: order, alignment, directional icons, numerals and mixed Latin/product strings are correct.
- [ ] Screenshots and store metadata use the same approved terminology as the app.

## Release evidence

- [ ] `python3 scripts/validate-localizations.py` passes.
- [ ] `scripts/validate-shell.sh --release` (or `--release-ads`) passes on macOS.
- [ ] The reviewer, locale, app version and date are recorded in the release notes.
