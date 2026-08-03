# Releasing the Windows build

Switcher3way for Windows ships through **two channels**, built from the same project:

| Channel | Build | Artifact | Signing | Updates |
|---|---|---|---|---|
| **Microsoft Store** | `build-msix.ps1` (`-p:Packaged=true`) | MSIX, ~45 MB | the **Store signs it** — no certificate needed | the Store |
| **Direct download** | `build-msi.ps1` | MSI, ~35 MB | unsigned → SmartScreen click-through | the in-app updater |

The app detects which flavour it is at runtime (`PackageInfo.IsPackaged`) and adapts: packaged
builds never self-update (Store policy) and use the package **StartupTask** for "start with
Windows" instead of a Startup-folder shortcut.

**Both packages bundle .NET.** MSIX declares a framework dependency on the Windows App Runtime, which
the Store resolves automatically, but there is no equivalent for the .NET runtime — a
framework-dependent package fails to launch on a PC without .NET 8, which would defeat the point of
the Store channel. `build-msix.ps1` therefore builds `-p:SelfContained=true` and refuses to finish if
.NET is missing from the package. That is why the MSIX is ~45 MB rather than the ~12 MB an earlier
framework-dependent build measured.

`build-msix.ps1` also copies each package to `windows/dist/` as
`Switcher3way-<version>-x64-{store,sideload}.msix` and prints its Publisher and signing state. Both
modes write the same `AppPackages` path, so without this a Store build silently overwrites a
dev-signed sideload package — and a dev-signed package is rejected on upload. The script hard-fails a
Store build whose Publisher is not the Partner Center one.

## Microsoft Store identity

These must match Partner Center exactly (note the capital **W** in `Switcher3Way`) — they live in
[`src/Switcher3way.App/Package.appxmanifest`](src/Switcher3way.App/Package.appxmanifest):

| Field | Value |
|---|---|
| Package/Identity/Name | `IronMade.Switcher3Way` |
| Package/Identity/Publisher | `CN=AF9BB38F-30B9-45AC-B73D-521C0053C310` |
| Package/Properties/PublisherDisplayName | `IronMade` |
| Package Family Name | `IronMade.Switcher3Way_zeh9vvkybnryc` |
| Store ID | `9MXFXL7GG3C5` |

**`runFullTrust` is a restricted capability.** Every submission (including updates) is reviewed by
hand and needs a justification along these lines:

> Switcher3way is a keyboard-layout utility. It installs a system-wide low-level keyboard hook
> (`WH_KEYBOARD_LL`) to detect a word typed in the wrong keyboard layout and uses `SendInput` to
> retype the corrected word; neither works inside the app container. The app is fully offline — no
> keystroke data is stored or transmitted — and password fields are explicitly excluded.

Store build + local certification run:

```powershell
pwsh windows/build-msix.ps1                        # package for Partner Center
pwsh windows/build-msix.ps1 -Sideload -Sign -Certify   # local install test + WACK (run elevated)
```

### Submission pack (paste into Partner Center)

**Privacy policy URL** — required, because a keyboard hook can access personal information:
`https://whiskeyswitch.github.io/Switcher3way/privacy.html` (source: [`docs/privacy.html`](../docs/privacy.html)).

**Restricted capability justification** (`runFullTrust`):

> Switcher3way is a keyboard-layout utility. It installs a system-wide low-level keyboard hook
> (`WH_KEYBOARD_LL`) to detect when a word has been typed in the wrong keyboard layout, and uses
> `SendInput` to retype the corrected word in the right one. Neither a system-wide hook nor input
> injection into other applications is possible inside the app container, so `runFullTrust` is
> required. The app works entirely offline: keystrokes for the current word are held in memory only
> and discarded at the next word boundary, nothing is stored or transmitted, and password fields are
> explicitly excluded from processing.

**Notes for certification** (reviewers must be told it is a tray app with no main window, or they
report that nothing launches):

> Switcher3way runs in the notification area — it has no main window. On first launch a short
> welcome flow appears; finish it to reach the tray icon.
>
> To test: add both an English and a Ukrainian (or Russian) keyboard layout in Windows. With the
> English layout active, open Notepad and type `ghbdsn` followed by a space — the text is replaced
> with `привіт` and the layout switches. Alternatively select any wrong-layout text and press the
> trigger key (a double tap of Ctrl by default) to convert it; press it again to cycle or undo.
>
> The tray icon's menu provides enable/disable, pause, Settings and Help. The app makes no network
> connections in this (Store) build.

**Also needed for the listing:** screenshots (1366×768 or larger) — the tray flyout, the Settings
window, and the conversion feedback chip are the useful three.

> The macOS release flow is separate — see `NOTES-3WAY.md` / `build_app.sh`.

## Prerequisites

- **.NET SDK** on PATH (`dotnet --version`). WiX is restored from NuGet by the installer project —
  no global WiX install needed.
- **GitHub CLI** authenticated (`gh auth status`) with push/release rights on
  `WhisKeySwitch/switcher3way-releases` (downloads) and `WhisKeySwitch/Switcher3way` (page).
- Work from a clean, merged `main`.

## 1. Pick the version

Bump `<Version>` in [`src/Switcher3way.App/Switcher3way.App.csproj`](src/Switcher3way.App/Switcher3way.App.csproj)
(drives both the **About** tab and the MSI `ProductVersion`). Keep it on its own Windows track —
it does **not** need to match the macOS version.

## 2. Build the MSI

```powershell
pwsh windows/build-msi.ps1 -Version 0.1.0
# → windows/installer/bin/Release/Switcher3way-<version>-win-x64.msi  (~55 MB)
```

The script publishes self-contained `win-x64` (bundles the .NET 8 Desktop runtime + `dict/`),
generates `installer/license.rtf` from the repo `LICENSE`, and builds the MSI. Close any running
`Switcher3way.exe` first (it locks the publish DLLs).

Sanity-check the payload without installing (no admin needed):

```powershell
$msi = "windows/installer/bin/Release/Switcher3way-0.1.0-win-x64.msi"
(Get-FileHash $msi -Algorithm SHA256).Hash.ToLower()          # note this for the release notes
msiexec /a $msi /qn TARGETDIR="$env:TEMP\s3w-check"           # admin-install = lay out all files
```

A real per-machine install needs elevation (UAC on double-click); a silent `/qn` from a
non-elevated shell returns **1925** by design — that's the privilege gate, not a defect.

## 3. Publish the GitHub release

Windows releases live on the **downloads repo** with a **Windows-specific tag** and are marked
**pre-release**. This is load-bearing, not cosmetic:

- `/releases/latest` (GitHub) **excludes pre-releases**, so the landing page's "Download for macOS"
  button and the macOS **in-app updater** keep resolving to the latest macOS **DMG**. The macOS
  updater (`Sources/Switcher3w/UpdateChecker.swift`) hits `/releases/latest` and requires a `.dmg`
  asset — a pre-release MSI is invisible to it on both counts.
- The **Windows** in-app updater (`windows/src/Switcher3way.App/UpdateChecker.cs`) does the opposite:
  it lists releases and offers the highest **`windows-v*`** tag. So publishing this pre-release is
  exactly what pushes the update to existing Windows users — make sure you bumped the app `Version`
  (step 1) first, or the new build reports the same version and no update is offered.
- Tag scheme: **`windows-v<version>`** (e.g. `windows-v0.1.1`) — distinct from macOS `v<version>`.

```powershell
$ver = "0.1.0"
$msi = "windows/installer/bin/Release/Switcher3way-$ver-win-x64.msi"
gh release create "windows-v$ver" "$msi" `
  -R WhisKeySwitch/switcher3way-releases `
  --title "Switcher3way for Windows $ver (preview)" `
  --notes-file windows/release-notes.md `
  --prerelease
```

Write the notes to include: install steps (MSI → UAC → SmartScreen *More info → Run anyway* because
unsigned), "no .NET needed", the **SHA-256**, and known limitations (unsigned, x64 only, no rewrite
inside elevated windows unless run as admin).

Verify afterwards:

```powershell
gh release view "windows-v$ver" -R WhisKeySwitch/switcher3way-releases --json isPrerelease,assets
gh release view -R WhisKeySwitch/switcher3way-releases --json tagName   # must still be the macOS vX.Y.Z
```

## 4. Update the landing page

The Windows **Download** buttons in [`../docs/index.html`](../docs/index.html) **and**
[`../docs/index.uk.html`](../docs/index.uk.html) point at the specific release tag (**not**
`/releases/latest`, which is macOS-only). Bump the button `href` and the Install-step link to the new
`windows-v<version>` tag in **both** pages, commit via a PR to `main`, and merge — GitHub Pages
redeploys `whiskeyswitch.github.io/Switcher3way/` from `docs/`. Existing Windows users also get the
update in-app once the pre-release is published.

## Not done yet (roadmap)

- **Code signing.** The MSI/exe are unsigned, so SmartScreen shows *"unknown publisher"*. This needs
  an **OV/EV certificate from a CA** (self-signed does not satisfy SmartScreen). Once available, wire
  `signtool sign` for the exe (before packaging) and the MSI (after) into `build-msi.ps1`.
- **arm64.** Only `win-x64` is built today.

Done: in-app auto-update (ships in 0.1.1+ — see `UpdateChecker.cs` / `UpdateInstaller.cs`).
