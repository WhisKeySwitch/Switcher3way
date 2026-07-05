#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="Switcher3w"   # SwiftPM build product / module name (can't start with a digit)
APP_NAME="Switcher3way"     # user-facing app + bundle name
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
# Universal-сборка кладёт продукт сюда (а не в .build/release)
BUILD_DIR="$PROJECT_DIR/.build/apple/Products/Release"
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

echo "=== Building $APP_NAME v$SHORT_VERSION (build $BUILD_VERSION) ==="

# 1. Собираем release — universal (arm64 + x86_64), чтобы работало и на Intel-маках
echo "→ swift build -c release --arch arm64 --arch x86_64 (universal)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# 2. Создаём .app bundle
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
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

# 5. Копируем иконку (имя файла = APP_NAME, чтобы совпадало с CFBundleIconFile)
cp "$PROJECT_DIR/Switcher3way.icns" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

# 5b. Генерируем встроенную справку из docs/user-guide*.md — руководства в репо
#     единственный источник правды; отсутствующий исходник валит сборку (см. scripts/md2html.py).
echo "→ Generating in-app help from docs/..."
/usr/bin/python3 "$PROJECT_DIR/scripts/md2html.py" "$PROJECT_DIR/docs" "$APP_BUNDLE/Contents/Resources/help"

# 6. Создаём PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 7. Подписываем СТАБИЛЬНЫМ self-signed сертификатом (см. signing/README). Designated
#    requirement привязан к фиксированному сертификату → выданные разрешения
#    Accessibility/Input Monitoring переживают пересборки. Ad-hoc — фолбэк, если ключа нет.
SIGN_ID="Switcher3way Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "→ Code signing with '$SIGN_ID'..."
    codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"
else
    echo "→ Stable identity not found — code signing ad-hoc (permissions won't persist across rebuilds)..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE" && echo "→ signature OK"

echo ""
echo "=== Done! ==="
echo "App bundle: $APP_BUNDLE"
echo "Signed: ad-hoc (right-click → Open on first launch on another Mac)"
echo ""
echo "To install:"
echo "  cp -R $APP_BUNDLE /Applications/"
