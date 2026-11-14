#!/bin/bash
# Builds "RAW Recipes.app" in build/ (requires Xcode).
#
#   ./build-app.sh                  build the app (universal: Apple silicon + Intel)
#   ./build-app.sh --package        also create a .dmg and a .zip in dist/ for a release
#   VERSION=1.2.0 ./build-app.sh    set the version shown in Finder and the About window
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="RAW Recipes"
EXECUTABLE="RAWRecipes"
VERSION="${VERSION:-0.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
PACKAGE=false
[[ "${1:-}" == "--package" ]] && PACKAGE=true

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Sources/RAWRecipes/Resources/Fonts "$APP/Contents/Resources/Fonts"
cp LICENSE "$APP/Contents/Resources/LICENSE" 2>/dev/null || echo "warning: LICENSE file missing"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run on your own Mac. Downloaded copies need the
# "Open Anyway" step described in the README until the app is notarized.
codesign --force --deep --sign - "$APP"
echo "Built: $APP ($VERSION)"

if $PACKAGE; then
    mkdir -p dist
    BASE="dist/RAW-Recipes-$VERSION-macOS"
    rm -f "$BASE.zip" "$BASE.dmg"

    ditto -c -k --keepParent "$APP" "$BASE.zip"

    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$BASE.dmg"
    rm -rf "$STAGING"

    echo "Packaged: $BASE.zip, $BASE.dmg"
fi
