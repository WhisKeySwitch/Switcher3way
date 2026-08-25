## 1. Establish the baseline (done — this is what motivated the change)

- [x] 1.1 Measure the package by kind: runtime 94.3%, dictionaries 5.2%, resources 0.5%.
- [x] 1.2 Price the dictionary split honestly: 2.2 MB compressed, under 5%. Rejected — see the proposal.
- [x] 1.3 Measure trimming: 45.9 MB → 14.5 MB compressed, 121 MB → 40 MB on disk (68%).
- [x] 1.4 Run the trimmed build rather than trusting the clean compile. It converts text correctly.
- [x] 1.5 Find what it breaks: browser password detection, the Settings window, settings loading.
- [x] 1.6 Record the negative result: `BuiltInComInteropSupport=true` does not restore COM — the
      marshalling stubs are already trimmed out (`System.StubHelpers.InterfaceMarshaler`) — and the
      package stays at exactly 14.5 MB, so the switch buys nothing.

## 2. Make the three defects survivable

- [x] 2.1 Settings: source-generated `JsonSerializerContext` instead of reflection-based
      `JsonSerializer`. Good practice regardless of trimming, and it removes every IL2026 on
      `SettingsManager`.
- [x] 2.2 XAML: `ILLink.Descriptors.xml` preserving WinUI, the projections and the SDK projection
      assembly, so markup extensions resolve. Settings now opens in a trimmed build.
- [x] 2.3 COM interop: `BuiltInComInteropSupport=true` **plus** preserving `System.StubHelpers`,
      `Marshal` and `__ComObject` in CoreLib — the switch alone is not enough, because the marshalling
      stubs are trimmed away regardless and the guard then fails with a different exception. Also
      preserved `Accessibility` and `Interop.UIAutomationClient`, which `SecureField` and
      `AccessibleCaret` reach only through `Type.InvokeMember`.
- [x] 2.4 `StartupShortcut` and `SettingsWindow` reach COM through `dynamic`; covered by the same
      descriptor rather than rewritten, since the interop they use is preserved wholesale.
- [x] 2.5 Re-measured. Roots give back 8 MB, as expected — the number that matters is the one after
      them:

      | | compressed | on disk |
      |---|---|---|
      | untrimmed | 45.9 MB | 121 MB |
      | trimmed, no roots (broken) | 14.5 MB | 40 MB |
      | **trimmed + roots (working)** | **22.6 MB** | **~60 MB** |

      A **51% saving**, against 2.2 MB for the dictionary split this change rejected.

## 3. Prove the guard, or abandon the change

The gate. None of these may be satisfied by inference from a clean build or from the app converting
text, both of which the broken trimmed build already does.

- [x] 3.1 `diagpw` against a focused password field in **Chrome**: `password=True (uia=True
      named=True)`, focused element `[name='Password' type=50004]`, and no "UI Automation
      unavailable" anywhere — identical to the untrimmed baseline built from the same source.

      Taking that baseline mattered. The first attempt showed `uia=False` on the trimmed build and
      looked like a failure; the untrimmed build said `uia=False` too. Chrome builds its renderer
      accessibility tree lazily, so until something asks for it the guard sees only a window pane
      (`type=50033`) rather than the field. Worth knowing on its own account: **browser password
      detection depends on Chrome's accessibility tree being up**, which this app's own repeated
      queries appear to bring up in normal use but which a freshly opened window may not have.
- [x] 3.2 Electron is Chromium, and on Windows both reach the app through the same UIA path — there is
      no separate mechanism to exercise, unlike macOS where Electron needs `AXManualAccessibility`.
      Covered by 3.1; recorded rather than contrived into a separate test.
- [ ] 3.3 **Not verified.** A classic Win32 password field still needs checking. Two attempts failed
      for reasons that are worth recording rather than retrying blindly: a credential dialog raised
      from PowerShell never became foreground, and a purpose-built `ES_PASSWORD` box was hosted by
      `powershell.exe` — which is in the denied-apps list, so the app correctly ignored it and logged
      nothing. A test host outside that list is needed.

      This is the lowest-risk item on the list, and that is the reason it is still open rather than
      quietly ticked: the signals it exercises (`ES_PASSWORD`, secure-input) are plain P/Invoke, which
      the trimmer keeps because the code calls it directly. What actually broke under trimming was the
      COM and reflection path, and that is what 3.1 verified.
- [x] 3.4 Settings opens in a trimmed build — window title `Switcher3way - Settings`, no
      `XamlParseException`, where the un-rooted trimmed build failed outright. Verified on the
      unpackaged trimmed build; XAML resolution does not differ between flavours, so this is the
      flavour-independent half. See 3.8 for what genuinely needed the packaged one.
- [x] 3.5 Settings load from an existing file, confirmed the only way that means anything: the debug
      log appears at all. `DebugLog` lives in that file, so its silence would have been the symptom —
      `buf:` lines are proof the value was read rather than defaulted.
- [x] 3.6 Detection and rewrite verified against the **trimmed packaged** build: `ghbdsn` converted to
      `привіт` and the layout followed, so the next word (`столиця`) needed no conversion at all.
      `verify-typo-guard.py` could not run its scripted layout switch this session — the Ukrainian
      layout is registered as the enhanced variant (`FFFFFFFFF0A80422`) and
      `WM_INPUTLANGCHANGEREQUEST` was refused — so the conversion path was exercised directly instead.
      Worth fixing in the harness separately; it is a limitation of the tool, not of the build.
- [x] 3.7 Caret chip positions itself (`chip: caret screen=… rcCaret=…`), which shares the COM
      accessibility path with the password guard and would have been the first thing to break.

- [x] 3.8 **Packaged-only:** `toast: registered` on the trimmed packaged build, so notifications
      survive trimming — the surface that has already cost this project two certification failures.
      `update: packaged build — the Store handles updates` confirms the packaged branch too.
- [x] 3.9 The trimmed **Store package** measures **23.1 MB against 46.7 MB — 50.5% off** what users
      download today.

## 4. Adopt or record

**Abandoned — deliberately, and with the measurements kept.**

- [x] 4.1 Not adopted. The decision was the owner's and the constraint was absolute: a size reduction
      that can break functionality is not acceptable, whatever it saves. That is the right reading of
      the evidence rather than a cautious one. Trimming's failure mode is not "it breaks loudly", it
      is "something nobody thought to test is silently gone" — this work found three such failures,
      two of them invisible from the outside, in an app that compiled cleanly and converted text
      perfectly. Nineteen checks passing says the paths we knew to worry about survive. It says
      nothing about the ones we did not think of, and by construction it cannot.
- [x] 4.2 Recorded in `windows/RELEASING.md` with the numbers, so a 50% saving stays a known and
      re-testable opportunity rather than folklore rediscovered in a year.
- [x] 4.3 The dictionary split is recorded as measured at 2.2 MB and rejected, with the condition that
      would change the answer: a fourth and fifth bundled language.

### What is kept, and why

The mechanism stays in the tree and stays **off**: `ILLink.Descriptors.xml`, the `PublishTrimmed`
conditions in the csproj, and `build-msix.ps1 -Trimmed`. None of it affects a shipped build — the
properties are conditioned on `PublishTrimmed`, which nothing sets.

This follows what was done with the erase strategies in `verify-the-old-text-is-gone`: the rejected
approaches stayed reachable behind `diagrewrite` precisely so the negative result stays a finding
that can be re-tested rather than an opinion handed down. Someone will propose trimming again. When
they do, the roots that make it nearly work, the measurement, and the reason it was declined are all
here.

### What would change the answer

Not a bigger saving — the saving was never the problem. It would take a way to establish that a
trimmed build is *whole*, rather than testing the paths we happen to remember. A crash-free run of
every UI surface and every interop path, driven automatically, would be a start. Until something like
that exists, "we tested the parts we thought of" is the strongest claim available, and it is not
strong enough for code that types into other people's password fields.
