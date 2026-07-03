# Stable code-signing identity

`build_app.sh` signs Switcher3way with a **self-signed certificate** named
`Switcher3way Self-Signed` instead of ad-hoc. Why: macOS ties Accessibility / Input Monitoring
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
