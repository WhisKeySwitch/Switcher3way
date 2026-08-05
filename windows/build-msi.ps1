<#
.SYNOPSIS
  Build the Switcher3way MSI (direct-download channel, per-machine, x64).

.DESCRIPTION
  The Microsoft Store channel is build-msix.ps1 — that package is smaller and Store-signed, so
  prefer it; this MSI exists for direct downloads. See RELEASING.md.

  1. Publishes with the .NET runtime bundled (no .NET prerequisite) but the Windows App SDK left as
     a runtime dependency: WinAppSDK self-contained cannot be produced in this environment, so the
     target PC needs "Windows App Runtime 1.6". The app shows a plain message if it is missing
     rather than exiting silently.
  2. Generates installer/license.rtf from the repo LICENSE (the MSI EULA page).
  3. Builds installer/Switcher3way.Installer.wixproj into an MSI under installer/bin.

  Requires the .NET SDK plus Visual Studio's MSIX/PRI build tooling (see Directory.Build.props).
  WiX is restored from NuGet by the wixproj (no global install needed).

.EXAMPLE
  pwsh windows/build-msi.ps1 -Version 0.2.5
#>
[CmdletBinding()]
param(
    [string]$Version = "0.2.5",
    [string]$Rid = "win-x64"
)

$ErrorActionPreference = "Stop"
$root      = Split-Path -Parent $MyInvocation.MyCommand.Path        # windows/
$repoRoot  = Split-Path -Parent $root
$appProj   = Join-Path $root "src\Switcher3way.App\Switcher3way.App.csproj"
$wixProj   = Join-Path $root "installer\Switcher3way.Installer.wixproj"
$stageDir  = Join-Path $root "publish\$Rid"
$licenseRtf= Join-Path $root "installer\license.rtf"

Write-Host "==> Publishing ($Rid, v$Version): .NET bundled, WinAppSDK as a runtime dependency..." -ForegroundColor Cyan
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
dotnet publish $appProj -c Release -r $Rid --self-contained true `
    -p:Platform=x64 -p:WindowsAppSDKSelfContained=false `
    -p:UseAppHost=true -p:Version=$Version -o $stageDir
if ($LASTEXITCODE -ne 0) { throw "publish failed" }

Write-Host "==> Generating license.rtf from LICENSE..." -ForegroundColor Cyan
# Two things this has to get right, both of which were wrong before and visibly corrupted the EULA
# page: a \par control word must be terminated by whitespace (otherwise "\parof" is read as an unknown
# control word and the following word is swallowed), and the lines must be joined with ONE \par —
# `-join '\par' + '\par'` evaluates the + first and joins with two.
$license = Get-Content (Join-Path $repoRoot "LICENSE") -Raw
$rtf = [System.Text.StringBuilder]::new()
[void]$rtf.Append('{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil Segoe UI;}}\fs18' + "`r`n")
foreach ($line in ($license -replace "`r`n", "`n").TrimEnd("`n").Split("`n")) {
    $esc = $line.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}')
    $out = [System.Text.StringBuilder]::new()
    foreach ($ch in $esc.ToCharArray()) {
        # Non-ASCII has to be escaped as \uN? or it renders as mojibake in the installer.
        if ([int]$ch -gt 127) { [void]$out.Append('\u' + [int]$ch + '?') } else { [void]$out.Append($ch) }
    }
    [void]$rtf.Append($out.ToString() + '\par' + "`r`n")   # newline terminates the control word
}
[void]$rtf.Append('}')
Set-Content -Path $licenseRtf -Value $rtf.ToString() -Encoding ASCII -NoNewline

# Guard against the exact regression: a \par immediately followed by a letter eats that word.
if ((Get-Content $licenseRtf -Raw) -match '\\par[A-Za-z]') { throw "license.rtf is malformed: \par is not delimited" }

Write-Host "==> Building MSI..." -ForegroundColor Cyan
# The WiX build can flake on its first invocation right after a publish (MSBuild node reuse);
# a plain retry succeeds. Disable the build server for this step and retry once to be safe.
$env:DOTNET_CLI_USE_MSBUILD_SERVER = "0"
# -p:Platform=x64 is required: without it WiX emits 32-bit components into a 64-bit directory (ICE80).
$wixArgs = @("-c", "Release", "-nodeReuse:false", "-p:Platform=x64",
             "-p:AppVersion=$Version", "-p:StageDir=$stageDir", "-p:LicenseRtf=$licenseRtf")
dotnet build $wixProj @wixArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "   first attempt failed; retrying..." -ForegroundColor Yellow
    dotnet build $wixProj @wixArgs
    if ($LASTEXITCODE -ne 0) { throw "MSI build failed" }
}

$msi = Get-ChildItem (Join-Path $root "installer\bin") -Filter *.msi -Recurse |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($msi) {
    Write-Host "`n==> MSI ready:" -ForegroundColor Green
    Write-Host ("    {0}  ({1:N1} MB)" -f $msi.FullName, ($msi.Length / 1MB))
    Write-Host "    NOTE: this channel requires 'Windows App Runtime 1.6' on the target PC." -ForegroundColor DarkGray
} else {
    throw "no MSI produced"
}
