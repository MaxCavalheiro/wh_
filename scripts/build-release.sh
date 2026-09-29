#!/bin/bash
#
# Builds wh_ for release and packages it as a DMG in dist/.
#
# The speech model is downloaded once (cached in ~/Library/Caches/wh-build) and shipped
# inside the app, so users never download it themselves: fetching 600 MB from inside an
# app is fragile on a busy connection, while a browser downloading the DMG resumes
# properly. This is what makes the DMG ~600 MB.
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

# Must match AppConfiguration.whisperModel when that is set, and be a folder in
# https://huggingface.co/argmaxinc/whisperkit-coreml
MODEL_REPO="argmaxinc/whisperkit-coreml"
MODEL_VARIANT="openai_whisper-large-v3-v20240930_626MB"
MODEL_CACHE="$HOME/Library/Caches/wh-build/$MODEL_VARIANT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk '/ MARKETING_VERSION =/ { print $3 }' | head -1)
fi
[ -n "$VERSION" ] || { echo "error: could not determine the version" >&2; exit 1; }

DMG_PATH="$DIST_DIR/${APP_NAME}_-${VERSION}.dmg"
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

fetch_model() {
    if [ -f "$MODEL_CACHE/.complete" ]; then
        echo "==> Speech model already cached"
        return
    fi
    echo "==> Fetching the speech model ($MODEL_VARIANT)"
    mkdir -p "$MODEL_CACHE"

    local files
    files=$(curl -fsSL "https://huggingface.co/api/models/$MODEL_REPO/tree/main/$MODEL_VARIANT?recursive=true" \
        | python3 -c 'import sys, json; print("\n".join(e["path"] for e in json.load(sys.stdin) if e["type"] == "file"))')
    [ -n "$files" ] || { echo "error: could not list the model files" >&2; exit 1; }

    while IFS= read -r path; do
        local target="$MODEL_CACHE/${path#"$MODEL_VARIANT/"}"
        mkdir -p "$(dirname "$target")"
        # -C - resumes, so an interrupted build does not start the 600 MB over.
        curl -fsSL -C - -o "$target" "https://huggingface.co/$MODEL_REPO/resolve/main/$path" \
            || { echo "error: failed to download $path" >&2; exit 1; }
        printf '.'
    done <<< "$files"
    echo

    for part in AudioEncoder.mlmodelc MelSpectrogram.mlmodelc TextDecoder.mlmodelc; do
        [ -d "$MODEL_CACHE/$part" ] || { echo "error: $part missing from the model" >&2; exit 1; }
    done
    touch "$MODEL_CACHE/.complete"
}

fetch_model

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

echo "==> Bundling the speech model"
rm -rf "$APP_PATH/Contents/Resources/WhisperModel"
cp -R "$MODEL_CACHE" "$APP_PATH/Contents/Resources/WhisperModel"
rm -f "$APP_PATH/Contents/Resources/WhisperModel/.complete"
# Adding resources invalidates the signature made during the build.
codesign --force --deep --sign - "$APP_PATH"

echo "==> Verifying"
codesign --verify --deep --strict "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"
du -sh "$APP_PATH/Contents/Resources/WhisperModel" | sed 's/^/model: /'
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
