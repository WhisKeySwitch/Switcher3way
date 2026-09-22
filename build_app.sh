#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="Switcher3w"   # SwiftPM build product / module name (can't start with a digit)
APP_NAME="Switcher3way"     # user-facing app + bundle name

# Two flavours from one source (see openspec/changes/ship-an-app-store-variant):
#
#   bash build_app.sh              direct     unsandboxed, Developer ID, self-updating
#   bash build_app.sh --appstore   App Store  sandboxed, updater compiled out
#
# Both produce a bundle called Switcher3way.app — the user-facing name is the same product —
# but in different directories and under different bundle identifiers, so both can be installed
# at once (one in /Applications, one in ~/Applications). That side-by-side install is not a
# convenience: the two flavours have DIFFERENT password-field protection, and comparing them is
# the only way to see it.
FLAVOUR="direct"
if [ "${1:-}" = "--appstore" ] || [ "${SWITCHER_APPSTORE:-0}" = "1" ]; then
    FLAVOUR="appstore"
fi

if [ "$FLAVOUR" = "appstore" ]; then
    export SWITCHER_APPSTORE=1          # read by Package.swift → -DSWITCHER_APPSTORE
    APP_BUNDLE="$PROJECT_DIR/dist/appstore/$APP_NAME.app"
    BUNDLE_ID="site.ironmade.switcher3way"
    ENTITLEMENTS="$PROJECT_DIR/signing/appstore.entitlements"
else
    unset SWITCHER_APPSTORE
    APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
    # Unchanged on purpose: this identifier holds the Accessibility and Input Monitoring grants
    # on every machine the app is already installed on. Changing it would drop them silently.
    BUNDLE_ID="com.switcher3way.app"
    ENTITLEMENTS=""
fi
# The products directory moves between toolchains (.build/apple/… on older SwiftPM,
# .build/out/… on the swiftbuild system), so ask the toolchain instead of hardcoding:
# a wrong guess here silently packages whatever stale binary the old path still holds.
BUILD_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
VERSION_JSON="$PROJECT_DIR/version.json"

# version.json — единый источник правды. Значения в Info.plist в репо
# игнорируются: скрипт штампует CFBundleShortVersionString и CFBundleVersion
# в копию Info.plist внутри собранного бандла.
SHORT_VERSION=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON'))['version'])")
BUILD_VERSION=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON')).get('build','1'))")
DEV_TAG=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON')).get('dev',''))")

if [ -z "$SHORT_VERSION" ]; then
    echo "ERROR: could not read version from $VERSION_JSON"
    exit 1
fi

echo "=== Building $APP_NAME v$SHORT_VERSION (build $BUILD_VERSION) — $FLAVOUR flavour ==="

# 1. Собираем release — universal (arm64 + x86_64), чтобы работало и на Intel-маках
echo "→ swift build -c release --arch arm64 --arch x86_64 (universal)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# 2. Создаём .app bundle
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$(dirname "$APP_BUNDLE")"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Копируем бинарник (SwiftPM собирает под PRODUCT_NAME, кладём как APP_NAME)
cp "$BUILD_DIR/$PRODUCT_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 3a. Самопроверка: бинарь обязан быть universal (arm64 + x86_64), иначе Intel-маки не запустят
ARCHS=$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
    echo "ERROR: бинарь не universal (получено: $ARCHS)"; exit 1
fi
echo "→ Universal OK: $ARCHS"

# 4. Копируем Info.plist и штампуем версию из version.json
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_BUNDLE/Contents/Info.plist"
# Dev-метка (буква) для непубликуемых сборок — пусто для релиза. Показывается в About/меню.
/usr/libexec/PlistBuddy -c "Set :RSDevTag $DEV_TAG" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :RSDevTag string $DEV_TAG" "$APP_BUNDLE/Contents/Info.plist"
echo "→ Stamped Info.plist: CFBundleShortVersionString=$SHORT_VERSION$DEV_TAG CFBundleVersion=$BUILD_VERSION"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
echo "→ Bundle identifier: $BUNDLE_ID"

# 4a. Stamp the Developer ID Team ID the updater will accept in a successor build.
#     Read from signing/developer-id.conf (sourced in step 7 below — do it early here so
#     the value lands in the plist before signing). This is what lets a build signed with
#     the LEGACY self-signed identity accept a Developer-ID-signed update: the team it
#     should trust travels inside its own signed bundle. Public information — the Team ID
#     appears in every signature the app ships with.
_conf="$PROJECT_DIR/signing/developer-id.conf"
if [ -f "$_conf" ] && [ -z "$TEAM_ID" ]; then
    # shellcheck disable=SC1090
    source "$_conf"
fi
# A Developer ID identity string ends in "(TEAMID)", so derive the team from it rather
# than having it typed twice and risk the two disagreeing. A wrong RSReleaseTeamID is not
# a recoverable mistake: it ships inside a signed bundle and decides which future builds
# that copy will accept.
if [ -z "$TEAM_ID" ] && [ -n "$DEVELOPER_ID_APP" ]; then
    TEAM_ID=$(printf '%s' "$DEVELOPER_ID_APP" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')
    if [ -n "$TEAM_ID" ]; then
        echo "→ Derived TEAM_ID=$TEAM_ID from the signing identity"
    fi
fi
if [ -n "$TEAM_ID" ] && ! printf '%s' "$TEAM_ID" | grep -qE '^[A-Z0-9]{10}$'; then
    echo "ERROR: TEAM_ID='$TEAM_ID' is not a 10-character Apple Team ID."
    echo "       Find it at developer.apple.com/account → Membership details."
    exit 1
fi
# A release with no team stamped can only accept successors by comparing certificate
# bytes, which stops working the day the certificate is re-issued — and by then the
# build is in the field and unfixable. Never ship one.
if [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ] && [ -z "$TEAM_ID" ]; then
    echo "ERROR: release build with an empty TEAM_ID."
    echo "       Set TEAM_ID in $_conf (developer.apple.com/account → Membership details)."
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :RSReleaseTeamID ${TEAM_ID}" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :RSReleaseTeamID string ${TEAM_ID}" "$APP_BUNDLE/Contents/Info.plist"
if [ -n "$TEAM_ID" ]; then
    echo "→ Stamped RSReleaseTeamID=$TEAM_ID (updater will accept this team's builds)"
else
    echo "→ RSReleaseTeamID empty — this build can only accept updates signed with the"
    echo "  identical certificate it carries (see signing/developer-id.conf)"
fi

# 5. Копируем иконку (имя файла = APP_NAME, чтобы совпадало с CFBundleIconFile)
cp "$PROJECT_DIR/Switcher3way.icns" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

# 5b. Генерируем встроенную справку из docs/user-guide*.md — руководства в репо
#     единственный источник правды; отсутствующий исходник валит сборку (см. scripts/md2html.py).
echo "→ Generating in-app help from docs/..."
/usr/bin/python3 "$PROJECT_DIR/scripts/md2html.py" "$PROJECT_DIR/docs" "$APP_BUNDLE/Contents/Resources/help"

# 6. Создаём PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 6a. App Store flavour: embed the provisioning profile. It must be in place BEFORE signing,
#     because the signature covers it. Without it the app has no App Store context: StoreKit
#     loads no products, so nothing about purchasing can be tested at all — and the failure is
#     an empty product list, which looks exactly like products not yet approved.
if [ "$FLAVOUR" = "appstore" ]; then
    PROFILE_PATH="$PROJECT_DIR/${PROVISION_PROFILE:-}"
    if [ -n "${PROVISION_PROFILE:-}" ] && [ -f "$PROFILE_PATH" ]; then
        cp "$PROFILE_PATH" "$APP_BUNDLE/Contents/embedded.provisionprofile"
        echo "→ Embedded provisioning profile: $(basename "$PROFILE_PATH")"
    else
        echo "→ WARNING: no provisioning profile at ${PROFILE_PATH:-<unset>}."
        echo "  StoreKit will load no products in this build and purchases cannot be tested."
    fi
fi

# 7. Sign. Three identities in descending order of preference; every one of them is
#    STABLE, which is the whole point — macOS ties Accessibility / Input Monitoring
#    grants to the designated requirement, so a changing identity drops the grants.
#
#    a) Developer ID Application (+ hardened runtime + secure timestamp) — the only
#       thing Apple will notarize, and therefore what ships. Local builds use it too
#       when it is available, so you test the signature that goes out rather than a
#       different one (the Windows port learned this the expensive way: verify in the
#       flavour that ships).
#    b) "Switcher3way Self-Signed" — the legacy fork identity. Development only now:
#       it cannot be notarized and Gatekeeper rejects it on any other Mac.
#    c) ad-hoc — last resort, permissions reset on every rebuild.
#
#    REQUIRE_DEVELOPER_ID=1 turns (b) and (c) into hard failures. create_dmg.sh sets it,
#    because a release DMG signed with anything else fails notarization halfway through
#    the build instead of here.
# Strip extended attributes before signing — quarantine flags and anything else the bundle picked
# up while being assembled. Must happen BEFORE signing, since the signature covers the bundle as
# it stands.
#
# This does NOT clear com.apple.provenance, which macOS re-applies to every file as it is written
# and which therefore appears as AppleDouble "._" entries in the package. That is normal and
# present in Xcode-built packages too; do not go chasing it.
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

DEV_ID_CONF="$PROJECT_DIR/signing/developer-id.conf"
if [ -f "$DEV_ID_CONF" ]; then
    # Environment wins over the file: `DEVELOPER_ID_APP=… bash build_app.sh` overrides.
    _env_dev_id="$DEVELOPER_ID_APP"; _env_team="$TEAM_ID"; _env_prof="$NOTARIZE_PROFILE"
    # shellcheck disable=SC1090
    source "$DEV_ID_CONF"
    # Plain `[ -n "$x" ] && y=…` would abort the script under `set -e` whenever the
    # variable is empty (the AND-list returns non-zero), so these stay as if-blocks.
    if [ -n "$_env_dev_id" ]; then DEVELOPER_ID_APP="$_env_dev_id"; fi
    if [ -n "$_env_team" ]; then TEAM_ID="$_env_team"; fi
    if [ -n "$_env_prof" ]; then NOTARIZE_PROFILE="$_env_prof"; fi
fi

LEGACY_SIGN_ID="Switcher3way Self-Signed"
HAVE_DEV_ID=0
if [ -n "$DEVELOPER_ID_APP" ] && security find-identity -p codesigning -v 2>/dev/null | grep -qF "$DEVELOPER_ID_APP"; then
    HAVE_DEV_ID=1
fi

if [ "$FLAVOUR" = "appstore" ]; then
    # The Mac App Store rejects a Developer ID signature outright. Different certificate,
    # different purpose: Developer ID vouches for software distributed outside the store.
    if ! security find-identity -p codesigning -v 2>/dev/null | grep -qF "${APPLE_DISTRIBUTION:-<unset>}"; then
        echo "ERROR: App Store flavour needs '${APPLE_DISTRIBUTION:-<unset>}' in the keychain."
        echo "       Set APPLE_DISTRIBUTION in $DEV_ID_CONF and check:"
        echo "         security find-identity -p codesigning -v"
        exit 1
    fi
    echo "→ Code signing with '$APPLE_DISTRIBUTION' (sandboxed, App Store)..."
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
             --sign "$APPLE_DISTRIBUTION" "$APP_BUNDLE"
    SIGNED_AS="'$APPLE_DISTRIBUTION' + $(basename "$ENTITLEMENTS") (App Store)"
elif [ "$HAVE_DEV_ID" = "1" ]; then
    echo "→ Code signing with '$DEVELOPER_ID_APP' (hardened runtime + timestamp)..."
    # No --deep: Apple deprecated it for Developer ID, and this bundle has nothing
    # nested to sign anyway (one binary + resources). --options runtime is mandatory
    # for notarization; --timestamp is what keeps the signature valid past cert expiry.
    if [ -n "$ENTITLEMENTS" ]; then
        codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
                 --sign "$DEVELOPER_ID_APP" "$APP_BUNDLE"
        SIGNED_AS="'$DEVELOPER_ID_APP' + $(basename "$ENTITLEMENTS") (sandboxed)"
    else
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP_BUNDLE"
        SIGNED_AS="'$DEVELOPER_ID_APP' (Developer ID, hardened runtime — notarizable)"
    fi
elif [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ]; then
    echo "ERROR: REQUIRE_DEVELOPER_ID=1 but no usable Developer ID Application identity."
    if [ -z "$DEVELOPER_ID_APP" ]; then
        echo "       DEVELOPER_ID_APP is empty — fill in $DEV_ID_CONF."
    else
        echo "       '$DEVELOPER_ID_APP' is not in the keychain. Check with:"
        echo "         security find-identity -p codesigning -v"
    fi
    echo "       Refusing to build a release that cannot be notarized."
    exit 1
# NOTE: no -v here. `-v` lists only TRUSTED identities, and a self-signed certificate
# never is (it reports CSSMERR_TP_NOT_TRUSTED). codesign signs with it perfectly well —
# trust only matters to Gatekeeper on someone else's Mac. With -v this branch could never
# match and every legacy build would silently drop to ad-hoc, resetting TCC grants.
elif security find-identity -p codesigning 2>/dev/null | grep -qF "$LEGACY_SIGN_ID"; then
    echo "→ No Developer ID — falling back to '$LEGACY_SIGN_ID' (DEVELOPMENT ONLY)."
    echo "  This build cannot be notarized and will not launch cleanly on another Mac."
    codesign --force --deep --sign "$LEGACY_SIGN_ID" "$APP_BUNDLE"
    SIGNED_AS="'$LEGACY_SIGN_ID' (legacy self-signed — development only, NOT shippable)"
else
    echo "→ No signing identity found — code signing ad-hoc (permissions won't persist across rebuilds)..."
    codesign --force --deep --sign - "$APP_BUNDLE"
    SIGNED_AS="ad-hoc (permissions reset on every rebuild — see signing/README.md)"
fi
codesign --verify --deep --strict "$APP_BUNDLE" && echo "→ signature OK"

echo ""
echo "=== Done! ==="
echo "App bundle: $APP_BUNDLE"
echo "Signed: $SIGNED_AS"
echo ""
echo "To install:"
echo "  cp -R $APP_BUNDLE /Applications/"
