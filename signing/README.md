# Code-signing identities

Two identities, and which one signs a build decides whether it can ship.

| | `Developer ID Application` | `Switcher3way Self-Signed` |
|---|---|---|
| Notarizable | yes — this is the only signature Apple accepts | no |
| Runs on another Mac | yes, no Gatekeeper prompt | no (right-click → Open, every time) |
| TCC grants survive rebuilds | yes | yes |
| Use for | **everything that ships** | development only, and only when no Developer ID is configured |

`build_app.sh` prefers Developer ID, falls back to the self-signed identity with a loud
warning, and falls back to ad-hoc if neither is in the keychain. `create_dmg.sh` sets
`REQUIRE_DEVELOPER_ID=1`, so a release build fails immediately rather than at the
notarization step twenty minutes later.

## Setting up Developer ID (one time)

1. In Xcode or on developer.apple.com, create a **Developer ID Application** certificate
   and install it in the login keychain. Confirm:

   ```bash
   security find-identity -p codesigning -v | grep "Developer ID Application"
   ```

2. Create an app-specific password at appleid.apple.com (Sign-In and Security →
   App-Specific Passwords), then store notarization credentials once:

   ```bash
   xcrun notarytool store-credentials switcher3way-notary \
       --apple-id <your Apple ID> --team-id <TEAM_ID> --password <app-specific password>
   ```

3. Fill in `signing/developer-id.conf` — the identity string, the Team ID, and the profile
   name from step 2. Environment variables of the same name override the file.

The Team ID is not a secret; it is embedded in every signature the app ships with. The
**certificate's private key is** — back it up, because losing it means a re-issued
certificate, and see "Why the Team ID is stamped into the bundle" below for why that is
survivable but a lost *account* is not.

## Why the Team ID is stamped into the bundle

`build_app.sh` writes `RSReleaseTeamID` into `Info.plist`. The updater
(`UpdateInstaller.verifySignatureMatchesRunningApp`) accepts a downloaded build if it
carries an Apple-anchored Developer ID signature issued to that team — **not** if its
certificate bytes match the running app's.

That indirection does two jobs. Developer ID certificates expire and are re-issued with a
different leaf certificate; a byte comparison would break the updater for every installed
copy on that day, with no way to push a fix. And it is what carries installs across the
migration *to* Developer ID: a build still signed with the self-signed identity accepts a
Developer-ID-signed successor, because the team it should trust travels inside its own
signed bundle. Fill the conf in **before** cutting the last self-signed release.

The `anchor apple generic` half of the check is not decorative. Signature validity alone
does not establish trust — a self-signed certificate can put any team string in its
subject OU, and macOS would consider that signature internally valid.

---

## The legacy self-signed identity

Before the fork had an Apple Developer account, `build_app.sh` signed Switcher3way with a
**self-signed certificate** named `Switcher3way Self-Signed` instead of ad-hoc. It is still
the development fallback. Why it exists: macOS ties Accessibility / Input Monitoring
grants to the app's *designated requirement*. Ad-hoc signing has no stable identity, so every
rebuild looked like a new app and dropped the grants. With a fixed certificate the requirement is:

```
identifier "com.switcher3way.app" and certificate leaf = H"5d799f0b…"
```

— identical on every rebuild, so **you grant permissions once and they persist**.

## Files here

- `cert.pem` — the public certificate (safe to keep/share).
- `cert.p12` — cert **+ private key**, password `sw3`. Importable backup. **Never commit / never put in the DMG** (git-ignored). Anyone with this can sign as this identity.

The active copy of the private key lives in your **login keychain** (that's what `codesign` uses).
`build_app.sh` falls back to ad-hoc automatically if the identity isn't found.

## Re-import on this or another Mac (if the keychain entry is lost)

```bash
security import signing/cert.p12 -k ~/Library/Keychains/login.keychain-db -P sw3 -T /usr/bin/codesign -A
security find-identity -p codesigning | grep Switcher3way   # confirm it's there
```

Then `bash build_app.sh` will pick it up. (It shows as `CSSMERR_TP_NOT_TRUSTED` — that's fine;
`codesign` still uses it. Trust only matters for Gatekeeper on *other* Macs, not for local TCC.)

## Recreate from scratch (if cert.p12 is lost)

Generating a new cert changes the certificate hash → the designated requirement changes → you'd
have to re-grant permissions once more. Steps are the same openssl + `security import` flow that
created this one (self-signed, `extendedKeyUsage=codeSigning`, legacy PKCS#12:
`-legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES`).
