# Releasing the Windows build

> **Status (August 2026).** The app is **live on the Microsoft Store**:
> [apps.microsoft.com/detail/9MXFXL7GG3C5](https://apps.microsoft.com/detail/9MXFXL7GG3C5). It took
> four submissions — three were rejected under **10.1.2.10 Functionality**, each for a different
> reason and each a real defect: the trigger answering with silence on a single-layout PC, the hook
> discarding all injected input (so nothing worked over Remote Desktop or an on-screen keyboard), and
> notification registration failing in the packaged flavour so every message the app produced was
> dropped. The pattern to learn from: **verify in the flavour that ships.** All three passed testing
> on an unpackaged build.
>
> Both channels are at **0.4.0** (the Store cleared certification on 24 August 2026).
> 0.2.8 was a Store-only submission; the MSI channel skipped it and went 0.2.7 → 0.2.9 → 0.3.0 → 0.4.0.
>
> **0.4.0 is the typo-guard release.** A user left for a competitor because every fumbled key threw a
> word into English and took the layout with it. Auto-fix now asks whether the typed text is a near
> miss of a word in the language being typed, and refuses to decide words under six characters without
> help from the surrounding phrase; measured typo-conversion went from 2.9% to 0% with paragraph-level
> recall unchanged. It also carries the rewrite-removal check held back from 0.3.0. Both are described
> in `openspec/changes/archive/2026-08-23-stop-converting-typos/` and
> `openspec/changes/archive/2026-08-19-verify-the-old-text-is-gone/`.
>
> **0.4.0 was the consolidation bridge for Windows.** Every MSI up to and including 0.3.0 polls the OLD
> downloads repo (`WhisKeySwitch/switcher3way-releases`) for updates, so 0.4.0 was published to **both**
> repos to let those installs reach the build that carries the new URL. Releases after this one go to
> the main repo only, and the old repo can be archived once the stragglers have crossed over (archived
> repos keep serving downloads and read-only API, so archiving does not strand anyone).
>
> **`-Version` does not stamp the package.** `build-msix.ps1 -Version 0.3.1` names the output file
> `Switcher3way-0.3.1-x64-sideload.msix` and sets the *assembly* version, but the package Identity comes
> from the hardcoded `Version="…"` in `Package.appxmanifest`, which the flag does not touch. Build a
> package without editing that line and you get one whose filename and identity disagree — which is how
> a test session ended up run against a completely different build than the one under test. **Edit
> `Package.appxmanifest` as well**, and check the result before trusting it:
>
> ```powershell
> python -c "import zipfile,re;print(re.search(r'<Identity[^>]*>', zipfile.ZipFile('windows/dist/<pkg>.msix').read('AppxManifest.xml').decode()).group(0))"
> ```
>
> **Reading a rewrite failure in the log.** Since 0.3.0 a replacement is verified by reading the text
> back, so `Result` says what happened rather than only whether SendInput accepted the events:
> `Ok` — read back and matches. `Mismatch` — landed wrong; the log carries `rewrite: MISMATCH — wanted
> "…", landed "…"`, the text was put back, and the manual cycle was abandoned. `Unverified` — the
> target exposes no readable text (Chromium before its accessibility tree exists, for instance); this
> is *not* a failure and is treated as applied. A `Mismatch` in a user's log is the line to ask for.
> It carries two figures added after 0.3.0: `[caret A -> B, expected C]` shows whether the right number of
> characters was removed, and `[trailing X -> Y]` shows whether the old text was left behind after the
> caret — a growing trailing count with a perfect caret figure means the replacement landed beside the
> original rather than over it.

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

### Architecture: x64 only, deliberately

Both channels ship **x64 only**. Windows on ARM runs x64 under emulation, and the parts most likely to
break there — a low-level keyboard hook and `SendInput` reaching native arm64 processes — are exactly the
parts that cannot be verified without arm64 hardware. Claiming arm64 support that nobody has run would be
worse than not offering it.

The project is not hard-wired to x64, so a native build is a change of parameters rather than of code:

```powershell
# app: RuntimeIdentifier/Platform/Platforms in Switcher3way.App.csproj currently pin x64
pwsh windows/build-msi.ps1 -Rid win-arm64      # also needs -p:Platform=ARM64 through the wixproj
pwsh windows/build-msix.ps1                    # -p:Platform=ARM64 -p:RuntimeIdentifier=win-arm64
```

Nothing in the detection stack blocks it: `WeCantSpell.Hunspell` is a managed implementation with no
native binary, so dictionaries and rendering are architecture-agnostic. What needs proving on real arm64
hardware is the input layer — that the hook sees keystrokes from native arm64 applications and that
`SendInput` rewrites text inside them — plus a Windows App SDK arm64 runtime and WiX emitting an arm64
package. Until someone can run that, the Store's architecture matching gives arm64 users the emulated x64
package, which is the honest position rather than an untested claim.

### Sideload testing: what bites

**Trusting the dev certificate takes two stores.** `Add-AppxPackage` is satisfied by the certificate in
`LocalMachine\TrustedPeople`, but double-clicking the `.msix` (App Installer) also wants the chain to
end at a trusted root and fails with **`0x800B010A`** — "the publisher certificate could not be
verified" — until the same self-signed certificate is *also* in `LocalMachine\Root`:

```powershell
$c = Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -eq AF3E5CA81DA3A215225702AD60AD34BA1FB5E060
Export-Certificate -Cert $c -FilePath "$env:TEMP\s3w-dev.cer"
# elevated:
Import-Certificate -FilePath "$env:TEMP\s3w-dev.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPeople
Import-Certificate -FilePath "$env:TEMP\s3w-dev.cer" -CertStoreLocation Cert:\LocalMachine\Root
```

Remove both afterwards — a machine-wide trusted root means anything signed with that key is trusted by
this PC, and the Store channel never needs it (the Store re-signs the package).

**Installing the sideload package removes the Store one.** They share the package Name
(`IronMade.Switcher3Way`) and differ only in publisher, and `Add-AppxPackage` replaces rather than
installs alongside — the Store entry simply disappears, along with its Start-menu tile and its
auto-start registration. Reinstall it from the Store when finished testing
([9MXFXL7GG3C5](https://apps.microsoft.com/detail/9MXFXL7GG3C5)). **No user data is lost**: settings
and logs live in `%APPDATA%\Switcher3way`, which is not redirected to `LocalCache`, so both flavours
read the same files and the swap is invisible to them.

**Only one of the two can run** for the same reason — the single-instance mutex and the data directory
are shared. Whichever starts first wins; stop one before launching the other.

**Notifications must be tested on the packaged build, not the MSI one.** `AppNotificationManager` is the
one API whose behaviour differs between the flavours: unpackaged it creates its own activator, packaged it
looks the activator up in the package's COM registration. A missing manifest declaration therefore breaks
every notification in the Store build only — it shipped that way in 0.2.6 and 0.2.7 and cost two
certification failures. `Switcher3way.exe diaghint` on a sideloaded package answers it in one line: the
log says either `toast: registered` or `toast: registration failed`.

### Submission pack (paste into Partner Center)

**Privacy policy URL** — required, because a keyboard hook can access personal information:
`https://whiskeyswitch.github.io/Switcher3way/privacy.html` (source: [`docs/privacy.html`](../docs/privacy.html)).

**Restricted capability justification** (`runFullTrust`) — answers Partner Center's "Why do you need
this capability, and how will it be used in your product?". Name the actual APIs: a reviewer can only
approve what they can picture.

**The field takes exactly 500 characters** (Submission options → Restricted capabilities) and truncates
silently rather than warning, so paste this version — it is 500 on the nose, single paragraph, no line
breaks:

> Switcher3way retypes words typed in the wrong keyboard layout (English/Ukrainian/Russian) and switches
> the layout. It must act inside whatever app the user types in, which the app container forbids:
> SetWindowsHookEx(WH_KEYBOARD_LL) to see keystrokes sent to other apps, SendInput to fix the text there,
> ActivateKeyboardLayout to switch its layout, Shell_NotifyIcon for the tray icon. Only the current word
> is held in memory, to the next word boundary. Password fields skipped. Nothing stored or sent.

The API list and the current-word-only lifetime are what earn the approval; drop anything else first.

*Medium form (~1,260 characters), if a future field is more generous:*

> Switcher3way fixes words typed in the wrong keyboard layout across English, Ukrainian and Russian: it
> detects that a finished word is nonsense in the active layout but a real word in another installed one,
> retypes it and switches the layout.
>
> That has to work in whatever application the user is typing in, which the app container prevents:
>
> - SetWindowsHookEx(WH_KEYBOARD_LL): see keystrokes going to other processes; a container app only gets
>   input aimed at its own windows.
> - SendInput: backspace the mistyped word and insert the corrected text into that application.
> - ActivateKeyboardLayout / WM_INPUTLANGCHANGEREQUEST: switch the foreground window's layout.
> - GetGUIThreadInfo and MSAA: locate the caret for the confirmation chip, and detect password fields so
>   they are skipped.
> - Shell_NotifyIcon: the notification-area icon (the app has no main window).
>
> Only the current word is held, in memory, and discarded at the next word boundary. Nothing typed is
> written to disk or transmitted — this build makes no network connections; dictionaries are bundled.
> Password fields, password managers and terminals are excluded, and the user can exclude any app.
>
> Open source (MIT), so every use of these APIs is verifiable:
> github.com/WhisKeySwitch/Switcher3way

*Long form, for a reviewer who comes back with questions:*

> **What the app does.** Switcher3way corrects words typed in the wrong keyboard layout across English,
> Ukrainian and Russian: it notices that a finished word is nonsense in the active layout but a real
> word in another installed one, retypes it correctly, and switches the layout. A manual trigger key
> does the same on demand for the last word or the current selection.
>
> **Why the app container cannot do this.** The feature is inherently system-wide — it has to observe
> and correct typing in whatever application the user is working in (Word, a browser, a chat window):
>
> - `SetWindowsHookEx(WH_KEYBOARD_LL)` to see keystrokes destined for *other* processes. There is no
>   sandboxed equivalent; an app-container process only receives input directed at its own windows.
> - `SendInput` to erase the mistyped word (backspaces) and insert the corrected text into the other
>   application's focused field. Injecting input into another process is likewise unavailable in the
>   container.
> - `ActivateKeyboardLayout` / `PostMessage(WM_INPUTLANGCHANGEREQUEST)` to switch the foreground
>   window's layout, and `GetKeyboardLayout(threadId)` to read it.
> - `GetGUIThreadInfo` and MSAA (`AccessibleObjectFromWindow`) to locate the caret — so the small
>   confirmation chip appears under the corrected word — and to detect password fields, which are
>   excluded from processing.
> - `QueryFullProcessImageName` to identify the foreground application, so per-application exclusions
>   and layout memory work.
> - `Shell_NotifyIcon` for the notification-area icon: the app has no main window.
>
> **How the data is handled.** Keystrokes for the *current word only* are held in memory and discarded
> at the next word boundary, or on any click, arrow key or application switch. Nothing typed is written
> to disk (an optional debug log is off by default) and nothing is transmitted: this Store build makes
> no network connections at all — dictionary checking uses Hunspell dictionaries bundled in the package.
> Password fields are excluded, password managers and terminals are excluded by default, and the user
> can exclude any other application or individual words. Reading a selection for the manual trigger
> sends one `Ctrl+C` and then restores the previous clipboard contents.
>
> **Verifiable.** The app is open source under the MIT licence — every use of these APIs can be read at
> https://github.com/WhisKeySwitch/Switcher3way. Privacy policy:
> https://whiskeyswitch.github.io/Switcher3way/privacy.html

**Notes for certification** — these go on **Supplemental info → Additional Testing Information**, not on
the Submission options page. That page only links to it, and leaving it empty is what keeps Submission
options marked *Incomplete* when a restricted capability is declared.

Two things will make a reviewer conclude the app is broken unless they are told: it has no main window,
and it does nothing until a second keyboard layout is installed. Both caused a certification failure —
the second one twice, so it now leads the notes.

> **First, add a second keyboard layout.** Settings → Time & language → Language & region → Add a
> language → **Ukrainian** (or Russian), alongside English. Switcher3way converts a word from one
> installed layout to another, so on a PC with a single layout there is nothing for it to convert
> between. **This step is required before any of the tests below will do anything.**
>
> **No main window.** Switcher3way runs in the notification area. On first launch a short welcome flow
> appears; finishing it leaves the app in the tray. Windows 11 hides new tray icons by default — if the
> flag icon is not visible, expand the notification area with the "^" chevron next to the clock. Click
> the icon for the menu (enable/disable, pause, Settings, Help).
>
> **Any keyboard works** — physical, the on-screen touch keyboard, or Remote Desktop. (Before 0.2.7 the
> app ignored all synthesized input and was inert on a tablet; that is fixed.)
>
> **The trigger always answers.** If it has nothing to convert — no second layout, nothing typed or
> selected, text already correct — it says so in a chip next to the cursor and in a notification, instead
> of doing nothing. (Before 0.2.8 the notification was discarded in the Store build, which is what the
> third certification failure saw.)
>
> **Test — automatic:** with the English layout active, open Notepad and type `ghbdsn` then a space. The
> text is replaced with `привіт`, the layout switches to Ukrainian, and a small chip appears under the
> word showing the change and the undo key.
>
> **Test — manual trigger:** select any text typed in the wrong layout and tap **Ctrl twice**. It
> converts in place; tapping again steps through the other layouts and then back to the original. The
> trigger is configurable in Settings → General.
>
> **Other notes.** No account, sign-in or credentials of any kind are required, and there are no
> purchases. This build makes no network connections. `runFullTrust` is used for a system-wide keyboard
> hook and `SendInput`; password fields are excluded from processing. x64 only.
>
> If you want a record of what the app detected, Settings → Advanced → Debug logging (off by default)
> writes to `%APPDATA%\Switcher3way\Logs\switcher3way.log`.

**Also needed for the listing:** screenshots (1366×768 or larger) — the tray flyout, the Settings
window, and the conversion feedback chip are the useful three.

> The macOS release flow is separate — see `NOTES-3WAY.md` / `build_app.sh`.

## Prerequisites

- **.NET SDK** on PATH (`dotnet --version`). WiX is restored from NuGet by the installer project —
  no global WiX install needed.
- **GitHub CLI** authenticated (`gh auth status`) with push/release rights on
  `WhisKeySwitch/Switcher3way` — releases live on the main repo itself since August 2026
  (consolidated from the old `switcher3way-releases` downloads repo).
- Work from a clean, merged `main`.

## 1. Pick the version

Bump `<Version>` in [`src/Switcher3way.App/Switcher3way.App.csproj`](src/Switcher3way.App/Switcher3way.App.csproj)
(drives both the **About** tab and the MSI `ProductVersion`). Keep it on its own Windows track —
it does **not** need to match the macOS version.

## 2. Build the MSI

```powershell
pwsh windows/build-msi.ps1 -Version 0.2.9
# → windows/installer/bin/x64/Release/Switcher3way-<version>-win-x64.msi  (~35 MB)
```

The script publishes self-contained `win-x64` (bundles the .NET 8 Desktop runtime + `dict/`),
generates `installer/license.rtf` from the repo `LICENSE`, and builds the MSI. Close any running
`Switcher3way.exe` first (it locks the publish DLLs).

Sanity-check the payload without installing (no admin needed):

```powershell
$msi = "windows/installer/bin/x64/Release/Switcher3way-0.2.9-win-x64.msi"
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
$ver = "0.2.9"
$msi = "windows/installer/bin/x64/Release/Switcher3way-$ver-win-x64.msi"
gh release create "windows-v$ver" "$msi" `
  -R WhisKeySwitch/Switcher3way `
  --title "Switcher3way for Windows $ver (preview)" `
  --notes-file windows/release-notes.md `
  --prerelease
```

> **One-time bridge (first Windows release after the August 2026 consolidation):** every MSI
> installed before that release polls the OLD repo (`WhisKeySwitch/switcher3way-releases`) for
> updates. Publish that first release to **both** repos (`gh release create … -R
> WhisKeySwitch/switcher3way-releases` with the same asset and notes) so existing installs can
> reach the build that carries the new URL — then archive the old repo (archived repos keep
> serving downloads and the API read-only, so stragglers still find the bridge). Every release
> after the bridge goes to the main repo only.

Write the notes to include: install steps (MSI → UAC → SmartScreen *More info → Run anyway* because
unsigned), "no .NET needed", the **SHA-256**, and known limitations (unsigned, x64 only, no rewrite
inside elevated windows unless run as admin).

Verify afterwards:

```powershell
gh release view "windows-v$ver" -R WhisKeySwitch/Switcher3way --json isPrerelease,assets
gh release view -R WhisKeySwitch/Switcher3way --json tagName   # must still be the macOS vX.Y.Z
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
