#!/bin/bash
set -e

APP_NAME="Switcher3way"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Единый источник версии — version.json в корне репозитория.
VERSION=$(/usr/bin/python3 -c "import json;print(json.load(open('version.json'))['version'])")
BUILD=$(/usr/bin/python3 -c "import json;print(json.load(open('version.json')).get('build','1'))")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
# Keychain profile used for Apple notarization. Override with NOTARIZE_PROFILE=<name>.
# Skip notarization entirely with SKIP_NOTARIZE=1.
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-notarytool-studio}"
DMG_TEMP="${APP_NAME}-temp.dmg"
VOL_NAME="${APP_NAME}"
BACKGROUND="dmg_background.png"
APP_PATH="${APP_NAME}.app"
DMG_SIZE="10m"

echo "=== Creating styled DMG ==="

# 0. ВСЕГДА пересобираем приложение из исходников. Без этого шага DMG берёт имя
#    из version.json, а payload — из случайно лежащего рядом Switcher3way.app.
#    Именно так в релиз 2.1.0 попал бандл 2.0.3: имя было 2.1.0, а внутри 2.0.3.
echo "→ Rebuilding app from source (build_app.sh)..."
"$SCRIPT_DIR/build_app.sh"

# 0a. Жёсткая проверка: версия в собранном бандле обязана совпадать с version.json,
#     иначе отказываемся паковать DMG.
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
BUNDLE_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
if [ "$BUNDLE_VERSION" != "$VERSION" ] || [ "$BUNDLE_BUILD" != "$BUILD" ]; then
    echo "ERROR: bundle is $BUNDLE_VERSION (build $BUNDLE_BUILD) but version.json is $VERSION (build $BUILD)."
    echo "       Refusing to ship a version-mismatched DMG."
    exit 1
fi
echo "→ Verified bundle $BUNDLE_VERSION (build $BUNDLE_BUILD) matches version.json"

# 0b. Нотаризуем и стейплим САМО приложение ДО упаковки — чтобы тикет был внутри .app.
#     Без этого вытащенный из DMG бандл не имеет своего тикета и при первом запуске
#     зависит от ОНЛАЙН-проверки Gatekeeper (после переноса/в офлайне → «не могу запустить»).
#     Со стейплом на бандле приложение запускается чисто офлайн, без xattr.
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    echo "→ Notarizing the app bundle..."
    ditto -c -k --keepParent "$APP_PATH" "${APP_NAME}-app.zip"
    xcrun notarytool submit "${APP_NAME}-app.zip" --keychain-profile "$NOTARIZE_PROFILE" --wait
    rm -f "${APP_NAME}-app.zip"
    echo "→ Stapling the app bundle..."
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
fi

# Clean up
rm -f "$DMG_NAME" "$DMG_TEMP"

# 0c. Снимаем «застрявшие» тома с тем же именем. Если /Volumes/Switcher3way уже занят,
#     наш temp-образ примонтируется как «Switcher3way 1», а AppleScript-оформление
#     (`tell disk "Switcher3way"`) уйдёт на чужой/несуществующий диск → .DS_Store с фоном
#     и позициями НЕ запишется в наш образ, и DMG откроется голым. Чистим заранее.
for v in "/Volumes/${VOL_NAME}"*; do
    if [ -d "$v" ]; then
        echo "→ Detaching stale volume: $v"
        hdiutil detach "$v" -force 2>/dev/null || true
    fi
done

# 1. Create temporary writable DMG
echo "→ Creating temp DMG..."
hdiutil create -volname "$VOL_NAME" -fs HFS+ \
    -size "$DMG_SIZE" -layout NONE "$DMG_TEMP"

# 2. Mount it
echo "→ Mounting..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$DMG_TEMP" | grep "/Volumes/" | sed 's/.*\(\/Volumes\/.*\)/\1/')
echo "   Mounted at: $MOUNT_DIR"
# Защита: если имя всё же разъехалось (том «Switcher3way 1») — оформление уйдёт мимо. Прерываемся.
if [ "$MOUNT_DIR" != "/Volumes/${VOL_NAME}" ]; then
    echo "ERROR: temp DMG mounted at '$MOUNT_DIR', expected '/Volumes/${VOL_NAME}'."
    echo "       Stale volume collision — refusing to build an unstyled DMG."
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    exit 1
fi

# 3. Copy app and create Applications symlink
echo "→ Copying app..."
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -sf /Applications "$MOUNT_DIR/Applications"

# 4. Create .background directory and copy background image
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.png"

# 5. Apply Finder settings via AppleScript
echo "→ Configuring Finder view..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"

        -- Position: app icon on left, Applications on right
        set position of item "$APP_NAME.app" of container window to {170, 210}
        set position of item "Applications" of container window to {490, 210}

        close
        open

        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

# 6. Set volume icon
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# 7. Finalize permissions
chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true
sync

# 7a. Проверяем, что Finder реально записал оформление. .DS_Store хранит фон и позиции
#     иконок; если его нет — DMG откроется голым. Лучше упасть, чем отдать кривой образ.
if [ ! -f "$MOUNT_DIR/.DS_Store" ]; then
    echo "ERROR: .DS_Store not written to $MOUNT_DIR — DMG styling did NOT apply."
    echo "       Refusing to ship an unstyled DMG."
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    exit 1
fi
echo "→ Styling OK (.DS_Store present)"

# 8. Unmount
echo "→ Unmounting..."
hdiutil detach "$MOUNT_DIR" -quiet

# 9. Convert to compressed read-only DMG
echo "→ Compressing..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"
rm -f "$DMG_TEMP"

# 9a. Подписываем САМ .dmg Developer ID. Без этого образ нотаризуется и стейплится, но
#     `spctl -t install` даёт "no usable signature" — у скачанного образа нет подписи
#     контейнера, и на части Mac это приводит к недоверию к вынутому из него .app.
SIGN_ID="Developer ID Application: Rashid Nasibulin (9GEWCZ59HK)"
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    echo "→ Code signing the DMG (Developer ID + secure timestamp)..."
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG_NAME"
    codesign --verify --verbose=2 "$DMG_NAME"
fi

# 10. Notarize with Apple (required for Gatekeeper to accept the DMG on end-user Macs).
# Signed-but-unnotarized DMGs trigger "Apple could not verify [app] is free of malware".
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "→ SKIP_NOTARIZE=1 — skipping notarization (DMG will NOT pass Gatekeeper on other Macs)"
else
    echo "→ Submitting to Apple notary service (profile: $NOTARIZE_PROFILE)..."
    xcrun notarytool submit "$DMG_NAME" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait

    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$DMG_NAME"
    xcrun stapler validate "$DMG_NAME"
    # Контрольная проверка: образ должен приниматься как установочный носитель.
    echo "→ Verifying DMG passes Gatekeeper (install assessment)..."
    spctl -a -vvv -t install "$DMG_NAME" 2>&1 || echo "WARNING: spctl install assessment did not pass"
fi

# 11. Записываем sha256 обратно в version.json — хэш механически привязан
#     к реально собранному DMG, а не копируется руками (раньше это расходилось).
#     (Homebrew cask удалён в чистке июля 2026 — форк не публикует релизы.)
DMG_SHA=$(shasum -a 256 "$DMG_NAME" | awk '{print $1}')
echo "→ Writing sha256 into version.json..."
/usr/bin/python3 - "$DMG_SHA" <<'PY'
import json, sys
sha = sys.argv[1]
with open("version.json") as f:
    data = json.load(f)
data["sha256"] = sha
with open("version.json", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
echo ""
echo "=== Done! ==="
echo "DMG: $(pwd)/$DMG_NAME ($(du -h "$DMG_NAME" | cut -f1))"
echo "SHA256: $DMG_SHA"
echo "→ version.json updated with this hash."
