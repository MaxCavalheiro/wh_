#!/bin/bash
#
# Builds wh_ for release and packages it as a DMG in dist/.
#
# The app is signed ad-hoc (no Apple Developer account needed), which is enough for
# macOS to run a sandboxed app locally, but not enough for Gatekeeper to trust a
# download: users have to allow it once in System Settings. See README.
#
# Usage: scripts/build-release.sh [version]     (default: MARKETING_VERSION from the project)

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="wh"
APP_NAME="wh"
BUILD_DIR="$(pwd)/build/release"
DIST_DIR="$(pwd)/dist"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk '/ MARKETING_VERSION =/ { print $3 }' | head -1)
fi
[ -n "$VERSION" ] || { echo "error: could not determine the version" >&2; exit 1; }

DMG_PATH="$DIST_DIR/${APP_NAME}_-${VERSION}.dmg"
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

echo "==> Building $APP_NAME $VERSION (universal)"
rm -rf "$BUILD_DIR"
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    | grep -E "error:|warning: .*\.swift|BUILD" || true

[ -d "$APP_PATH" ] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

echo "==> Verifying"
codesign --verify --deep --strict "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"
# get-task-allow lets a debugger attach to the app; it belongs to debug builds only.
if codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "get-task-allow"; then
    echo "error: release build carries the get-task-allow entitlement" >&2
    exit 1
fi

echo "==> Packaging DMG"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "${APP_NAME}_ ${VERSION}" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

echo
echo "Done: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo "SHA-256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
