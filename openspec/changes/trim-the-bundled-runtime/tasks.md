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
- [ ] 3.2 The same in an Electron application, which raises the tree through `AXManualAccessibility`.
- [ ] 3.3 The same against a classic Win32 password field, which uses the secure-input flag and should
      never have depended on COM.
- [ ] 3.4 Settings, Help and the welcome flow all open — the existing "An installed build can open its
      windows" requirement, checked rather than assumed.
- [ ] 3.5 Settings load from an existing file: confirmed by the debug log actually appearing, since
      `DebugLog` living in that file makes its silence the symptom.
- [ ] 3.6 The typo-guard end-to-end pass (`windows/tools/verify-typo-guard.py`) against the trimmed
      packaged build.
- [ ] 3.7 Caret chip positioning, which shares the COM accessibility path with the guard.

## 4. Adopt or record

- [ ] 4.1 If 3.1–3.7 all hold: adopt in `build-msix.ps1` and `build-msi.ps1`, and state the new
      download size in the release notes — it is the most user-visible thing in the release.
- [ ] 4.2 If any of them cannot be made to hold: **abandon**, and write the finding into
      `windows/RELEASING.md` with the measurements, so the 68% stays a known and re-testable
      opportunity rather than something rediscovered and re-attempted from scratch.
- [ ] 4.3 Either way, record that the dictionary split was measured at 2.2 MB and rejected, and note
      the condition that would change that answer: a fourth and fifth bundled language.
