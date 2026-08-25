## Why

The Windows package is 46.7 MB, and almost none of that is the app.

| | compressed in the MSIX | share |
|---|---|---|
| .NET + WinUI runtime | 44.0 MB | 94.3% |
| dictionaries (all three languages) | 2.4 MB | 5.2% |
| icons, manifest, resources | 0.25 MB | 0.5% |

The obvious-looking economy — ship English only and download Ukrainian and Russian on demand — is
worth **2.2 MB, under 5%**. Hunspell dictionaries are text and compress about six to one: `uk.dic` is
8.9 MB on disk and 1.58 MB on the wire. It would buy a downloader, a second dictionary root (an MSIX
install directory is read-only), per-dictionary licences, version skew against the app, and a new
failure mode where adding Ukrainian while offline leaves a language that silently detects nothing —
which is both this app's worst failure shape and the category that produced three certification
rejections under 10.1.2.10. That trade is not worth 2.2 MB, and this change does not propose it. It
becomes the right design at the fourth or fifth language, not at the third.

**The runtime is where the weight is, and trimming it was measured, not estimated:**

| | compressed | on disk |
|---|---|---|
| today | 45.9 MB | 121 MB |
| `PublishTrimmed`, `TrimMode=partial` | **14.5 MB** | **40 MB** |
| saving | **31.4 MB (68%)** | 81 MB |

That is roughly fourteen times what the dictionary split offers. `System.Private.Xml` (3.58 MB),
`System.Data.Common` (1.33 MB) and `System.Private.DataContractSerialization` (0.91 MB) are shipped
today and nothing in the source references them.

## Why this is a proposal and not a patch

The trimmed build compiles with warnings only, launches, and **converts text correctly**. It also
does this, which is why the change is gated rather than applied:

```
secure: UI Automation unavailable, browser password fields will NOT be detected:
        Built-in COM has been disabled via a feature switch.
settings open failed: Microsoft.UI.Xaml.Markup.XamlParseException
```

Three defects, of which the first is the reason for every gate below:

1. **The password guard loses browser detection.** `SecureField` answers `false` — "not a password" —
   on any failure, deliberately, so that the guard can never block typing. Under trimming that means
   the app would convert and retype inside password fields in Chrome, Edge and Electron applications.
   This is the guard that already shipped broken for four releases on an untested assumption.
2. **Settings cannot open** — a trimmed XAML markup extension. The existing spec already forbids
   shipping this ("An installed build can open its windows"); trimming breaks it quietly.
3. **Settings never load** — `JsonSerializer` reflection is trimmed away, so every preference falls
   back to defaults. Handled separately in `fix-silent-settings-reset`, which is worth doing on its
   own account.

**A recorded negative result:** `BuiltInComInteropSupport=true` does *not* fix (1). The trimmer has
already removed the marshalling stubs, so the guard fails with `Could not load type
'System.StubHelpers.InterfaceMarshaler'` instead — same breakage, different exception, and the
package is exactly the same 14.5 MB. The cheap escape does not exist; the COM paths need explicit
trimmer roots.

## What Changes

- Make the three defects survivable — source-generated JSON, trimmer roots for the WinUI/XAML and COM
  interop paths — and **re-measure**, because roots give size back and the saving must be worth
  having after they are added.
- **Gate adoption on the password guard being proven, by test, in a real browser.** Not inferred from
  a clean build, and not from the app converting text, which it does regardless. If the guard cannot
  be demonstrated working in a trimmed build, this change is abandoned and the finding recorded — the
  same way the erase speed-up was abandoned rather than shipped unmet.
- Add the missing rule to the spec: a packaging or build-configuration change SHALL NOT be adopted if
  it disables a safety guard, and a guard that fails open SHALL be verified after any such change.

## What this change does not propose

- **Downloading the .NET runtime instead of bundling it.** Not available where it would help. MSIX can
  declare a framework dependency on the Windows App Runtime because Microsoft publishes one in the
  Store; there is no equivalent for .NET, a Store app cannot run an installer, and "installing it from
  the Store is sufficient to run it" is an existing requirement. For the direct-download channel a WiX
  bundle could chain the runtime, but the artifact becomes an `.exe` while `UpdateChecker` looks for a
  `.msi` asset — an updater migration, for a saving trimming already delivers with no prerequisite.
- **Splitting the dictionaries**, for the reasons in the first section.
EOF
