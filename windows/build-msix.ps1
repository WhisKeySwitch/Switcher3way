<#
.SYNOPSIS
  Build the Switcher3way MSIX package (Microsoft Store build).

.DESCRIPTION
  Produces the packaged flavour of the app (-p:Packaged=true). The Store signs submitted packages,
  so no code-signing certificate is needed for the submission itself — but a package must be signed
  to be *installed locally*, so use -Sign for sideload testing with the self-signed dev certificate.

  Modes:
    (default)     StoreUpload — the .msixupload to attach in Partner Center
    -Sideload     SideloadOnly — a plain .msix you can install locally for testing
    -Sign         sign a sideload package with the dev certificate (see signing/README-windows.md)
    -Certify      run the Windows App Certification Kit against the built package

  Requires the .NET SDK and Visual Studio's MSIX/PRI build tooling (the UWP workload); see
  windows/Directory.Build.props.

.EXAMPLE
  pwsh windows/build-msix.ps1 -Version 0.2.0                 # Store upload package
  pwsh windows/build-msix.ps1 -Sideload -Sign -Certify       # local test + certification run
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$Sideload,
    [switch]$Sign,
    [switch]$Certify
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path      # windows/
$proj = Join-Path $root "src\Switcher3way.App\Switcher3way.App.csproj"
$outDir = Join-Path $root "src\Switcher3way.App\AppPackages"

$mode = if ($Sideload) { "SideloadOnly" } else { "StoreUpload" }
$signing = if ($Sign) { "true" } else { "false" }

$args = @(
    $proj, "-t:Publish", "-restore",
    "-p:Configuration=Release", "-p:Platform=x64", "-p:RuntimeIdentifier=win-x64",
    "-p:Packaged=true",
    "-p:UapAppxPackageBuildMode=$mode",
    "-p:AppxPackageSigningEnabled=$signing",
    "-p:AppxPackageDir=$outDir\"
)
if ($Version) { $args += "-p:Version=$Version" }
if ($Sign) {
    # The stable self-signed dev identity — for local sideload testing only.
    $args += "-p:PackageCertificateThumbprint=AF3E5CA81DA3A215225702AD60AD34BA1FB5E060"
}

Write-Host "==> Building MSIX ($mode)..." -ForegroundColor Cyan
dotnet msbuild @args -v:m -nologo
if ($LASTEXITCODE -ne 0) { throw "MSIX build failed" }

$pkg = Get-ChildItem $outDir -Recurse -Include *.msixupload, *.msix -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -notlike "Microsoft.WindowsAppRuntime*" } |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $pkg) { throw "no package produced" }

Write-Host "`n==> Package ready:" -ForegroundColor Green
Write-Host ("    {0}  ({1:N1} MB)" -f $pkg.FullName, ($pkg.Length / 1MB))

if ($Certify) {
    $appcert = "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe"
    if (-not (Test-Path $appcert)) { throw "App Certification Kit not found — install it with the Windows SDK" }
    $report = Join-Path $outDir "wack-report.xml"
    Write-Host "`n==> Running the Windows App Certification Kit (needs elevation, takes a few minutes)..." -ForegroundColor Cyan
    & $appcert reset
    & $appcert test -appxpackagepath $pkg.FullName -reportoutputpath $report
    Write-Host "    report: $report"
}

Write-Host @"

Before submitting to Partner Center:
  • Package.appxmanifest Identity Name/Publisher must match the values Partner Center shows
    under Product identity (they are placeholders in the repo).
  • runFullTrust is a restricted capability: justify it in the submission notes (system-wide
    keyboard hook + SendInput cannot work inside the app container; nothing leaves the device).
"@ -ForegroundColor DarkGray
