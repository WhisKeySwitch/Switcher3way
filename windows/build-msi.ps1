<#
.SYNOPSIS
  Build the Switcher3way Windows installer (self-contained MSI, per-machine, x64).

.DESCRIPTION
  1. Publishes the app self-contained for win-x64 (bundles the .NET 8 Desktop runtime, so the
     target PC needs no .NET prerequisite) into publish/win-x64.
  2. Generates installer/license.rtf from the repo LICENSE (the MSI EULA page).
  3. Builds installer/Switcher3way.Installer.wixproj into an MSI under installer/bin/Release.

  Requires the .NET SDK. WiX is restored from NuGet by the wixproj (no global install needed).

.EXAMPLE
  pwsh windows/build-msi.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = "0.1.0",
    [string]$Rid = "win-x64"
)

$ErrorActionPreference = "Stop"
$root      = Split-Path -Parent $MyInvocation.MyCommand.Path        # windows/
$repoRoot  = Split-Path -Parent $root
$appProj   = Join-Path $root "src\Switcher3way.App\Switcher3way.App.csproj"
$wixProj   = Join-Path $root "installer\Switcher3way.Installer.wixproj"
$stageDir  = Join-Path $root "publish\$Rid"
$licenseRtf= Join-Path $root "installer\license.rtf"

Write-Host "==> Publishing self-contained ($Rid, v$Version)..." -ForegroundColor Cyan
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
dotnet publish $appProj -c Release -r $Rid --self-contained true `
    -p:UseAppHost=true -p:Version=$Version -o $stageDir
if ($LASTEXITCODE -ne 0) { throw "publish failed" }

Write-Host "==> Generating license.rtf from LICENSE..." -ForegroundColor Cyan
$license = Get-Content (Join-Path $repoRoot "LICENSE") -Raw
$esc = $license -replace '\\', '\\\\' -replace '\{', '\{' -replace '\}', '\}'
$esc = ($esc -split "`r?`n") -join '\par' + '\par'
$rtf = "{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil Segoe UI;}}\fs18 $esc}"
Set-Content -Path $licenseRtf -Value $rtf -Encoding ASCII -NoNewline

Write-Host "==> Building MSI..." -ForegroundColor Cyan
# The WiX build can flake on its first invocation right after a publish (MSBuild node reuse);
# a plain retry succeeds. Disable the build server for this step and retry once to be safe.
$env:DOTNET_CLI_USE_MSBUILD_SERVER = "0"
dotnet build $wixProj -c Release -nodeReuse:false `
    -p:AppVersion=$Version -p:StageDir=$stageDir -p:LicenseRtf=$licenseRtf
if ($LASTEXITCODE -ne 0) {
    Write-Host "   first attempt failed; retrying..." -ForegroundColor Yellow
    dotnet build $wixProj -c Release -nodeReuse:false `
        -p:AppVersion=$Version -p:StageDir=$stageDir -p:LicenseRtf=$licenseRtf
    if ($LASTEXITCODE -ne 0) { throw "MSI build failed" }
}

$msi = Get-ChildItem (Join-Path $root "installer\bin\Release") -Filter *.msi -Recurse |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($msi) {
    Write-Host "`n==> MSI ready:" -ForegroundColor Green
    Write-Host ("    {0}  ({1:N1} MB)" -f $msi.FullName, ($msi.Length / 1MB))
} else {
    throw "no MSI produced"
}
