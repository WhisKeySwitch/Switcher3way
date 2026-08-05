# Tasks — Windows MVP

Reconciled against the shipped app on 5 August 2026 (release 0.2.3, Store submission in review).

This is the original MVP change: it built the detection core, the live loop and the first tray/settings
UI on WinForms. The **WinUI 3 redesign** (archived as `2026-08-05-windows-winui3-redesign`) then replaced
the whole UI layer and changed how the app is distributed, so several items here are superseded rather
than outstanding. Those are marked `[—]` with what replaced them.

## 1. Signing + CI foundation

Superseded as a group. The premise was that an unsigned build would not launch on managed devices, so
the MVP needed an OSS code-signing certificate through SignPath and a CI pipeline to use it. Distribution
moved to the **Microsoft Store**, which signs submitted packages itself — that removes the "unknown
publisher" warning without any certificate of ours, which was the one blocker we could not solve. See
decision 13 in the archived redesign.

- [—] 1.1 SignPath Foundation application — never pursued; the Store signs the package.
- [x] 1.2 Windows solution scaffolded (`Switcher3way.Core` + tests). Still the structure in use.
- [—] 1.3 GitHub Actions + SignPath signing request — no signing pipeline exists; the Store handles it
  for the packaged channel and the MSI ships unsigned by choice.
- [—] 1.4 Authenticode-sign and timestamp both exe and installer — not done and not planned for the MSI.
  A self-signed dev certificate exists for *sideload testing only* (`windows/RELEASING.md`).
- [x] 1.5 Runs on this machine unsigned; the original block was a managed ASR rule, since removed. The
  clean-managed-device check is folded into 7.3 below, still open.

## 2. Portable detection core (C#, no Win32)

- [x] 2.1 `Switcher3way.Core` — resolver, soft gates, letter-core trimming, OS bindings behind interfaces.
- [x] 2.2 Unit tests against macOS behaviour (27 tests at the time; the suite still guards this core).

## 3. Offline dictionaries (Hunspell)

- [x] 3.1 `WeCantSpell.Hunspell` (managed, no native binary) + bundled en/ru/uk dictionaries with their
  licences. Still true, and it is why an arm64 build would not need native rebuilds.
- [x] 3.2 Dictionary quality measured 5 August 2026, against a checked-in fixture rather than a macOS
  `NSSpellChecker` capture: the point was never agreement with Apple but whether the dictionaries accept
  and reject the words that decide a conversion. **170/171 accept · 38/38 reject** across everyday
  vocabulary, 2-letter words, inflected nouns and verbs, declined adjectives, ё and ё-omitted spellings,
  apostrophe forms, loanwords, proper nouns, and the cross-layout renders that must be refused. No false
  accepts — the direction that would corrupt text. The one false reject is `Kyiv`, absent from en_US
  (SCOWL); English proper nouns are thin while ru/uk carry Москва/Київ/Україна/Львів. Fixture:
  `windows/tests/Switcher3way.Core.Tests/DictionaryQualityTests.cs`; findings in `DICTIONARIES.md`.
- [x] 3.3 Validation behind `IDictionaryValidator`; end-to-end test through `NWayResolver`.

## 4. Live detection loop

- [x] 4.1 Win32 patterns graduated from the spike: layout catalog, key classifier, hook + word buffer,
  layout switcher, text rewriter.
- [x] 4.2 Auto path in `Engine`, operator-verified live on real typing.
- [x] 4.3 Manual trigger + N-way cycle, with the buffer-reset guards. The trigger has since moved from F9
  to a double tap of Ctrl (0.2.2), and now also converts a selection.
- [x] 4.4 Throwaway spike code removed, `FINDINGS.md` kept as the record.

## 5. Parity features

- [—] 5.1 WinForms tray (`TrayApp`) — replaced by the Win32 tray + Fluent flyout, and the file was deleted
  in the deferred-work branch (PR #58).
- [—] 5.2 WinForms settings window (`SettingsForm`) — replaced by the WinUI Settings window; file deleted.
  Settings persistence (`SettingsManager` → `%AppData%\Switcher3way\settings.json`) survives unchanged.
- [x] 5.3 Exceptions: denied apps with defaults, never/always-convert word lists, enforced in `Engine` and
  editable in the UI, plus password-field detection. Was partial here; completed by the redesign's
  unified exceptions list, and password detection now uses `ES_PASSWORD` + MSAA rather than UIA.
- [x] 5.4 Per-app layout memory via a foreground watcher, gated on a setting.
- [x] 5.5 Interface localization — **completed in 0.2.3**, after the redesign had left ~50 new strings
  hard-coded in English. English, Ukrainian and Russian are complete; the thirteen inherited languages
  fall back to English and are labelled as incomplete in the picker.
- [x] 5.6 Opt-in rotating file log, off by default.
- [x] 5.7 Elevated-window handling: a refused or short `SendInput` raises a throttled notification. The
  balloon tip became a real Windows notification in PR #58.

## 6. Packaging, distribution, docs

- [x] 6.1 Shell framework and installer format chosen: **WinUI 3** with a **WiX MSI** for direct download
  and **MSIX** for the Store. Recorded as decisions 12–13 in the archived redesign.
- [—] 6.2 Signed, timestamped installer through the phase-1 pipeline — superseded with 1.3/1.4. Releases
  are published from a local build with a SHA-256 in the notes; `windows/RELEASING.md` is the procedure.
- [x] 6.3 Windows build and release loop documented — `windows/RELEASING.md` covers both channels, the
  Store identity, the submission pack, sideload certificate trust, and why the build is x64 only. The
  SignPath part of this task is void.

## 7. Validation and sign-off

- [~] 7.1 EN↔RU and EN↔UK auto and manual conversion verified by the operator in Notepad (Win32). **UWP
  and Electron targets remain unverified for conversion** — and note that verification needs a human:
  the hook ignores synthetic input by design, so no script can stand in.
- [ ] 7.2 Verify the exclusions behave per spec (denied apps, password fields, elevated windows) — the
  code paths exist and are unit-covered where they are testable, but no deliberate end-to-end pass has
  been run against a password manager, a browser login form and an elevated window.
- [~] 7.3 Fully-offline operation confirmed (the Store build makes no network calls at all; the MSI build
  only contacts GitHub for update checks, which can be turned off). **The signed-on-EDR half is void** —
  there is no signed exe; the Store package is signed by Microsoft, which is the answer for managed
  devices going forward.
