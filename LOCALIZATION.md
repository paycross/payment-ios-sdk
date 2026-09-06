# Localizing the PayCross iOS sheet

The payment sheet ships **English and French**. This file lists every string it
draws, says what each one paints, and gives the rule that decides which language
a shopper sees.

## Languages

| Language | Tag | Where it comes from |
|---|---|---|
| English | `en` | `Sources/PayCross/Resources/en.lproj/Localizable.strings` |
| French | `fr` | `Sources/PayCross/Resources/fr.lproj/Localizable.strings` |

Both files carry the same 32 keys. A test fails the build if one ever gains a key
the other lacks, or if a translation drops a `%@`.

## Which language a shopper sees

Three sources, in order of preference:

1. `PayCrossAPI.configure(locale:)` — the merchant's own choice.
2. The checkout session's `locale`, as the server sent it.
3. The shopper's device preferences, most preferred first.

They are matched **one candidate at a time**: exact tag first (`fr`), then
primary subtag (`fr-CA` → `fr`). The first candidate naming a language the SDK
ships wins. A candidate it cannot speak is **passed over**, not treated as the
final answer, so a merchant asking for German over a French session gets the
French sheet. When nothing matches, the sheet is English.

Case does not matter and `_` is accepted in place of `-`, so `FR_ca` resolves. A
tag that parses to nothing is skipped. No input to this makes it throw.

```swift
// Nothing set: the session decides, else the device, else English.
PayCrossAPI.configure(environment: .sandbox)

// The merchant's app already knows the shopper reads French.
PayCrossAPI.configure(environment: .sandbox, locale: "fr")

// The SDK ships no German. The sheet falls through to the session's language,
// then to the device's, and is English only if neither speaks one it ships.
PayCrossAPI.configure(environment: .sandbox, locale: "de")
```

The language is resolved twice per payment: once before the sheet appears, from
the override and the device, and again the moment the session arrives, which is
the only source that can still change the answer. It is forgotten when the sheet
is dismissed.

## Amounts

The amount is **not** clamped to the two languages the SDK ships. It is
formatted in the first locale anybody supplied — the override, else the session,
else the device's first preference — with its region intact, **provided that
candidate is shaped like a language tag**: two or three letters, then any number
of short alphanumeric subtags. One that is not — `français`, `f-r`, `fr-`, `f` —
is passed over and the next candidate formats the amount instead, so a typo
cannot both pick the wrong words and misprint the price.

`_` is read as `-` throughout, on both halves, so a merchant handing over
`Locale.current.identifier` and getting `fr_FR` gets French words and French
digits rather than one of each.

A well-formed tag for a language the SDK ships no strings for, such as `frr`,
gives English words and still formats the amount as itself.

Foundation writes currency for every locale, not just the two the SDK has words
for, and a shopper who cannot read the labels can still read the price. So:

| Override | Session | Device | Words | Amount |
|---|---|---|---|---|
| — | — | `de-DE` | English | `12,34 €` |
| — | `fr-CH` | `en-US` | French | Swiss French |
| `fr` | — | `en-US` | French | `12,34 €` |
| — | — | — | English | `€12.34` |

The region matters here where it does not for the words: `fr-CH` and `fr-FR` are
one language and two number formats.

## Overriding the words

Define any of these keys in your **own** app's `Localizable.strings` and your
wording replaces ours for that one label. Every key is prefixed `paycross_`, so
an override happens because you asked for it and never by accident.

**An explicit `locale:` does not switch overrides off.** They answer different
questions: one says which language, the other says which words. Your bundle is
searched first whatever language the sheet resolved to. Your override is resolved
against *your* app's own localizations, so an app that ships French strings gives
French overrides to a French shopper, and an English-only app gives its English
ones in both languages.

Localizing the sheet into a language the SDK does not ship is the same mechanism:
supply the keys you want, in your app's `.lproj` for that language.

## Every key

`%@` marks a value the SDK substitutes at runtime. **An override of a key that
carries one must keep it**, or the card, amount or field name it names is lost.

Only a literal `%@` is substituted. Any other percent in your override — `%d`,
`%s`, `%1$@` — is left exactly as you wrote it and is never read as a format
specifier, so the worst a typo costs you is a label with a `%d` in it.

### The card form

| Key | What it paints | `%@` |
|---|---|---|
| `paycross_total` | Caption above the amount | |
| `paycross_pay_amount` | The Pay button | the formatted amount |
| `paycross_or_pay_with_card` | Separator between the Apple Pay button and the fields | |
| `paycross_cardholder_name` | Label above the cardholder name field | |
| `paycross_name_on_card` | Placeholder inside that field | |
| `paycross_card_number` | Label above the card number field | |
| `paycross_expiry_label` | Label above the expiry field | |
| `paycross_cvv` | Label above the security code field | |
| `paycross_save_this_card` | The toggle offering to store the card | |
| `paycross_keyboard_done` | Button above the numeric keypad | |

`paycross_expiry_label` is translated (`MM/YY` → `MM/AA`) but the field still
takes `MM/YY` digits in every language. It is a hint, not a format.

### Stored cards

| Key | What it paints | `%@` |
|---|---|---|
| `paycross_use_a_new_card` | The row that switches back to card entry | |
| `paycross_remove_card` | VoiceOver label on a row's delete button | the row, e.g. `Visa •••• 1111` |
| `paycross_remove_card_title` | Title of the delete confirmation | |
| `paycross_remove_card_message` | Body of that confirmation | the row being deleted |
| `paycross_remove_card_confirm` | The button that deletes | |
| `paycross_remove_card_failed` | Shown when the delete failed | |

### The sheet itself

| Key | What it paints |
|---|---|
| `paycross_payment` | Title of the sheet, and of the 3-D Secure screen over it |
| `paycross_cancel` | The cancel button, and the one on the 3-D Secure screen |
| `paycross_cancel_payment_title` | Title of the cancel confirmation |
| `paycross_cancel_payment_yes` | Confirms the cancellation |
| `paycross_cancel_payment_continue` | Dismisses it and keeps paying |
| `paycross_cancel_payment_message` | Body of the cancel confirmation |
| `paycross_session_expired` | Shown when the session can take no more payments |

### Errors

| Key | What it paints | `%@` |
|---|---|---|
| `paycross_error_payment_failed` | Banner on the re-armed form after a retryable decline | |
| `paycross_error_network` | Banner when the submission never reached the server | |
| `paycross_error_submission_failed` | Banner when the server refused it and sent no sentence of its own | |
| `paycross_field_required` | A required server-driven field was left blank | the field's label |
| `paycross_field_invalid` | That field failed the server's pattern | the field's label |

The server can send its own message for a field or a submission. When it does,
that message wins over both languages: it is written for that one merchant and it
is not translatable.

### Apple Pay

| Key | What it paints | `%@` |
|---|---|---|
| `paycross_apple_pay_not_configured` | The merchant has no Apple Pay merchant identifier | |
| `paycross_error_apple_pay_busy` | A second Apple Pay sheet was asked for while one was open | |
| `paycross_error_apple_pay_presentation` | Apple's sheet refused to present | the merchant identifier |
| `paycross_error_apple_pay_token` | Apple Pay returned a token the SDK could not read | |

`paycross_error_apple_pay_presentation` is written for whoever integrates the
SDK, not for a shopper: it names the app's Apple Pay entitlement and the merchant
identifier the SDK asked with. It is translated so no shopper meets raw English,
but the key still greps out of a French bug report.

## Where these strings come from in the code

Most are looked up in the SwiftUI views through `L(key, englishFallback)`.

Five live in `PayCrossCore`, which is free of UIKit so it builds on Linux and
therefore cannot call `L` at all: `paycross_error_payment_failed`,
`paycross_error_network`, `paycross_error_submission_failed`,
`paycross_field_required` and `paycross_field_invalid`. The sheet resolves those
five on the main actor and hands them to Core as a `FlowMessages` value before a
payment starts.
