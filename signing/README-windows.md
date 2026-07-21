# Windows code signing

Two separate concerns, for two purposes. See also the macOS signing notes in `README.md`.

## 1. Local dev identity — stable self-signed cert (this machine only)

A self-signed code-signing certificate for signing **local development builds** of the Windows app
— the Windows parallel of the macOS stable self-signed cert. Important caveat: on Windows you don't
actually *need* it to run dev builds (see "The ASR caveat" below); it exists so local builds carry a
consistent, `Valid` signature if you want one.

**The identity**
- Subject: `CN=Switcher3way Self-Signed (Dev)`
- Thumbprint: `AF3E5CA81DA3A215225702AD60AD34BA1FB5E060`
- SHA-256 / RSA, Code Signing EKU, valid 2026-07-21 → 2031-07-21
- Location: `Cert:\CurrentUser\My` (private key), trusted via `CurrentUser\Root` + `CurrentUser\TrustedPublisher`

**Recreate (if lost)** — elevated PowerShell:
```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
  -Subject "CN=Switcher3way Self-Signed (Dev)" `
  -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(5)
foreach ($n in 'Root','TrustedPublisher') {   # trust locally so signatures validate + launch
  $s = [System.Security.Cryptography.X509Certificates.X509Store]::new($n,'CurrentUser')
  $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
}
```

**Sign a build** (timestamped):
```powershell
$c = Get-Item Cert:\CurrentUser\My\AF3E5CA81DA3A215225702AD60AD34BA1FB5E060
Set-AuthenticodeSignature -FilePath .\Switcher3way.exe -Certificate $c `
  -HashAlgorithm SHA256 -TimestampServer "http://timestamp.digicert.com"
(Get-AuthenticodeSignature .\Switcher3way.exe).Status   # -> Valid
```

**Back it up** (survives a machine change — mirrors macOS `cert.p12`):
```powershell
$pw = Read-Host -AsSecureString "PFX password"
Export-PfxCertificate -Cert Cert:\CurrentUser\My\AF3E5CA81DA3A215225702AD60AD34BA1FB5E060 `
  -FilePath signing\switcher3way-dev.pfx -Password $pw
```
`signing/*.pfx` is git-ignored — **never commit it.** Restore with `Import-PfxCertificate`, then
re-trust (Root + TrustedPublisher) as above.

## 2. Release signing — NOT self-signed

Self-signed is trusted only where you install it. Distribution needs a publicly-trusted,
reputation-backed certificate:
- **SignPath Foundation** (free for OSS) once the project passes their adoption/reputation review, or
- a paid **EV** certificate for instant SmartScreen reputation.

See `openspec/changes/windows-mvp/` decision **M4**.

## The ASR caveat — why signing ≠ "it will launch"

The dev machine originally blocked the freshly-built exe with "Access is denied". The cause was
**not** a missing signature — it was a managed **Attack Surface Reduction** rule, *"Block executable
files from running unless they meet a prevalence, age, or trusted-list criterion"*
(`01443614-cd74-433a-b99e-2ecdc07bfc25`), pushed via device management (Defender Exploit Guard event
1121). That rule judges **Microsoft-cloud prevalence**, not local signature validity — so:

- A **self-signed** cert (even `Valid` and locally trusted) is **still blocked** by the rule.
- With the rule disabled (unmanaged machine), an **unsigned** exe launches fine.

So local signing is optional for dev, and only a reputation-backed / **EV** signature (not
self-signed) clears the same rule + SmartScreen on end-user machines.
