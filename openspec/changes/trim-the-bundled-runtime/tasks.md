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

- [ ] 2.1 Settings: source-generated `JsonSerializerContext` instead of reflection-based
      `JsonSerializer`. Good practice regardless of trimming, and it removes every IL2026 on
      `SettingsManager`. (`fix-silent-settings-reset` makes the failure loud; this makes it not happen.)
- [ ] 2.2 XAML: trimmer roots / descriptors for WinUI and the app assembly so markup extensions resolve.
      WinUI 3 does not officially support trimming — if this cannot be made to hold, stop here and
      record it.
- [ ] 2.3 COM interop: preserve the paths `SecureField` and `AccessibleCaret` depend on
      (`AccessibleObjectFromWindow`, `IAccessible`, `Type.InvokeMember` over accessibility objects)
      with explicit `DynamicDependency` attributes or a trimmer root descriptor.
- [ ] 2.4 `StartupShortcut` and `SettingsWindow` use `dynamic` over COM ProgIDs; replace with typed
      interop or preserve explicitly.
- [ ] 2.5 **Re-measure.** Roots give size back. If the saving after roots is not clearly worth the
      risk this change is documenting, abandon it — the number that matters is the one at the end.

## 3. Prove the guard, or abandon the change

The gate. None of these may be satisfied by inference from a clean build or from the app converting
text, both of which the broken trimmed build already does.

- [ ] 3.1 `diagpw` against a focused password field in **Chrome or Edge** — the case that needs the
      accessibility path — reporting a real verdict rather than "UI Automation unavailable".
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
