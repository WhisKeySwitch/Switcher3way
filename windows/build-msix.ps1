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

# SelfContained bundles .NET into the package. It is not optional for the Store: MSIX can declare a
# framework dependency on the Windows App Runtime (and does, below), but there is no equivalent for
# the .NET runtime — a framework-dependent package simply fails to launch on a PC without .NET 8, and
# "no prerequisites" is the whole reason the Store build exists. WindowsAppSDKSelfContained stays
# false so the WinAppSDK keeps coming from its framework package.
$args = @(
    $proj, "-t:Publish", "-restore",
    "-p:Configuration=Release", "-p:Platform=x64", "-p:RuntimeIdentifier=win-x64",
    "-p:Packaged=true", "-p:SelfContained=true", "-p:WindowsAppSDKSelfContained=false",
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

# Both modes write the same AppPackages path, so a Store build silently overwrites a dev-signed
# sideload package (and vice versa) — and the two are indistinguishable by name while differing in
# exactly the way that matters: a dev-signed package has the wrong Publisher and is rejected on
# upload. Copy each to a name that says which it is, and verify what actually came out.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($pkg.FullName)
try {
    function Read-Entry($name) {
        $e = $zip.GetEntry($name)
        if (-not $e) { return $null }
        $r = New-Object System.IO.StreamReader($e.Open())
        try { $r.ReadToEnd() } finally { $r.Dispose() }
    }
    $publisher   = ([xml](Read-Entry "AppxManifest.xml")).Package.Identity.Publisher
    $signed      = $null -ne $zip.GetEntry("AppxSignature.p7x")
    $bundledNet  = $null -ne $zip.GetEntry("System.Private.CoreLib.dll")
} finally { $zip.Dispose() }

# Without .NET in the package the app cannot start on a PC that has no .NET 8 runtime, which is the
# one promise the Store build makes. Never let that ship.
if (-not $bundledNet) { throw "package is framework-dependent on .NET — rebuild with -p:SelfContained=true" }
if ($Sideload) {
    if (-not $signed) { Write-Warning "sideload package is unsigned — it cannot be installed locally (use -Sign)" }
} else {
    if ($publisher -ne "CN=AF9BB38F-30B9-45AC-B73D-521C0053C310") {
        throw "Store package has the wrong Publisher ($publisher) — a dev-signed build cannot be uploaded"
    }
    if ($signed) { Write-Warning "Store package is signed; Partner Center expects to sign it itself" }
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$version = if ($Version) { $Version } else { "dev" }
$copy = Join-Path $dist ("Switcher3way-$version-x64-" + $(if ($Sideload) { "sideload" } else { "store" }) + $pkg.Extension)
Copy-Item $pkg.FullName $copy -Force

Write-Host "`n==> Package ready:" -ForegroundColor Green
Write-Host ("    {0}  ({1:N1} MB)" -f $copy, ((Get-Item $copy).Length / 1MB))
Write-Host ("    built at {0}" -f $pkg.FullName) -ForegroundColor DarkGray
Write-Host ("    Publisher: {0}" -f $publisher)
Write-Host ("    signed: {0}   .NET bundled: {1}" -f $signed, $bundledNet)

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
  • Identity is set to the real product identity (Store ID 9MXFXL7GG3C5) — bump -Version for a
    new submission; the revision field must stay 0.
  • runFullTrust is a restricted capability: justify it in the submission notes (system-wide
    keyboard hook + SendInput cannot work inside the app container; nothing leaves the device).
    The wording lives in windows/RELEASING.md.
"@ -ForegroundColor DarkGray
