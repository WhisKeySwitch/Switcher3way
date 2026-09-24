#!/bin/bash
# Builds the Mac App Store submission package.
#
#   bash build_appstore_pkg.sh
#
# The store takes a signed .pkg, not a DMG — create_dmg.sh serves the direct channel only and has
# nothing to do with this path. Upload the result with Transporter, or:
#   xcrun altool --upload-package dist/appstore/Switcher3Way.pkg -t macos \
#                --apple-id <app apple id> --bundle-id site.ironmade.switcher3way \
#                --bundle-version <build> --bundle-short-version-string <version> \
#                --keychain-profile switcher3way-notary
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Switcher3way"          # bundle filename; the user-facing name is CFBundleDisplayName
APP_BUNDLE="$PROJECT_DIR/dist/appstore/$APP_NAME.app"
PKG_OUT="$PROJECT_DIR/dist/appstore/Switcher3Way.pkg"

DEV_ID_CONF="$PROJECT_DIR/signing/developer-id.conf"
if [ -f "$DEV_ID_CONF" ]; then
    # shellcheck disable=SC1090
    source "$DEV_ID_CONF"
fi

echo "=== Building the App Store package ==="
echo "→ Building the sandboxed app..."
bash "$PROJECT_DIR/build_app.sh" --appstore

# The profile is what gives the app its App Store context. Without it the package can still be
# built and even uploaded, but StoreKit loads no products in any local test — so refuse here
# rather than let someone spend an evening debugging an empty product list.
if [ ! -f "$APP_BUNDLE/Contents/embedded.provisionprofile" ]; then
    echo "ERROR: no embedded.provisionprofile in the built bundle."
    echo "       Download the Mac App Store profile for site.ironmade.switcher3way, save it to"
    echo "       ${PROVISION_PROFILE:-signing/…provisionprofile}, and build again."
    exit 1
fi

if [ -z "${INSTALLER_DISTRIBUTION:-}" ]; then
    echo "ERROR: INSTALLER_DISTRIBUTION is not set in $DEV_ID_CONF."
    exit 1
fi
if ! security find-identity -p basic -v 2>/dev/null | grep -qF "$INSTALLER_DISTRIBUTION"; then
    echo "ERROR: '$INSTALLER_DISTRIBUTION' is not in the keychain."
    echo "       This is the INSTALLER certificate — separate from the app one, and the app"
    echo "       certificate cannot sign a package."
    exit 1
fi

# Self-check before packaging: the store rejects both of these, and finding out from a failed
# upload costs a round trip through Apple rather than a second here.
# Capture each command's output in full before inspecting it. Piping straight into `grep -q`
# closes the pipe as soon as it matches, and codesign reports the failed write as
# "write: Permission denied" — an alarming message on a run that succeeded, which is exactly how
# people learn to stop reading build output.
SIG_INFO=$(codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 || true)
AUTHORITY=$(printf '%s\n' "$SIG_INFO" | grep "^Authority=" | head -1 | cut -d= -f2-)
case "$AUTHORITY" in
    "Apple Distribution"*) ;;
    *) echo "ERROR: app is signed by '$AUTHORITY', not Apple Distribution. The store will reject it."; exit 1 ;;
esac

# Matched with `case`, not a pipe into `grep -q`: grep exits on its first match and the shell
# reports the builtin's write to the closed pipe as "write: Permission denied" — a permission
# error printed by a run that succeeded.
ENTS=$(codesign -d --entitlements - "$APP_BUNDLE" 2>/dev/null || true)
case "$ENTS" in
    *app-sandbox*) ;;
    *) echo "ERROR: app is not sandboxed. The Mac App Store requires the sandbox."; exit 1 ;;
esac
case "$ENTS" in
    *application-identifier*) ;;
    *) echo "ERROR: no application-identifier entitlement — it must match the provisioning profile."
       echo "       Upload is rejected for a profile/entitlement mismatch without it."
       exit 1 ;;
esac
echo "→ Signed by: $AUTHORITY, sandboxed, profile embedded"

rm -f "$PKG_OUT"
echo "→ productbuild..."
productbuild --component "$APP_BUNDLE" /Applications \
             --sign "$INSTALLER_DISTRIBUTION" "$PKG_OUT"

echo "→ Verifying the package signature..."
PKG_SIG=$(pkgutil --check-signature "$PKG_OUT" 2>&1 || true)
echo "$PKG_SIG" | sed -n '1,6p'
case "$PKG_SIG" in
    *"3rd Party Mac Developer Installer"*) ;;
    *) echo "ERROR: the package is not signed by the installer certificate."; exit 1 ;;
esac

echo ""
echo "=== Done! ==="
echo "Package: $PKG_OUT ($(du -h "$PKG_OUT" | cut -f1))"
echo "Upload it with Transporter, or xcrun altool --upload-package (see the header of this file)."
