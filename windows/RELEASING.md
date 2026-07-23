# Releasing the Windows build

How to cut a Switcher3way **Windows** release: build the installer, publish it to the public
downloads repo, and update the landing page. The Windows app is versioned **independently** of
macOS (started at `0.1.0`, preview) and ships as a **self-contained MSI** — the target PC needs
no .NET installed.

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
  button and the macOS **in-app updater** keep resolving to the latest macOS **DMG**.
- The macOS updater (`Sources/Switcher3w/UpdateChecker.swift`) hits `/releases/latest` and requires
  a `.dmg` asset — a pre-release MSI is invisible to it on both counts.
- Tag scheme: **`windows-v<version>`** (e.g. `windows-v0.1.0`) — distinct from macOS `v<version>`.

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
unsigned), "no .NET needed", the **SHA-256**, and known limitations (unsigned, x64 only, no
auto-update, no rewrite inside elevated windows unless run as admin).

Verify afterwards:

```powershell
gh release view "windows-v$ver" -R WhisKeySwitch/switcher3way-releases --json isPrerelease,assets
gh release view -R WhisKeySwitch/switcher3way-releases --json tagName   # must still be the macOS vX.Y.Z
```

## 4. Update the landing page

The Windows **Download** button in [`../docs/index.html`](../docs/index.html) points at the specific
release tag (**not** `/releases/latest`, which is macOS-only). Bump both the button `href` and the
Install-step link to the new `windows-v<version>` tag, commit via a PR to `main`, and merge —
GitHub Pages redeploys `whiskeyswitch.github.io/Switcher3way/` from `docs/`.

## Not done yet (roadmap)

- **Code signing.** The MSI/exe are unsigned, so SmartScreen shows *"unknown publisher"*. This needs
  an **OV/EV certificate from a CA** (self-signed does not satisfy SmartScreen). Once available, wire
  `signtool sign` for the exe (before packaging) and the MSI (after) into `build-msi.ps1`.
- **Auto-update on Windows.** The in-app updater is macOS-only; Windows users check this page/releases.
- **arm64.** Only `win-x64` is built today.
