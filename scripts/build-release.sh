#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

APP_NAME="Sideman"
EXECUTABLE_NAME="SidemanApp"
BUNDLE_NAME="$APP_NAME.app"

# ---------------------------------------------------------------------------
# 1. Determine version
# ---------------------------------------------------------------------------
if [[ ${1:-} ]]; then
    VERSION="$1"
elif git -C "$PROJECT_ROOT" describe --tags --exact-match HEAD 2>/dev/null | grep -qE '^v'; then
    VERSION="$(git -C "$PROJECT_ROOT" describe --tags --exact-match HEAD | sed 's/^v//')"
else
    VERSION="0.0.0-dev"
fi
echo "==> Version: $VERSION"

# ---------------------------------------------------------------------------
# 2. Build
# ---------------------------------------------------------------------------
ARCH="${ARCH:-}"
if [[ "$ARCH" == "universal" ]]; then
    echo "==> Building universal binary (arm64 + x86_64)..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch arm64 --arch x86_64
else
    echo "==> Building release binary..."
    swift build -c release --package-path "$PROJECT_ROOT"
fi

# Locate the built executable
BIN_PATH="$(swift build -c release --package-path "$PROJECT_ROOT" --show-bin-path)/$EXECUTABLE_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "ERROR: Built executable not found at $BIN_PATH" >&2
    exit 1
fi
echo "==> Executable: $BIN_PATH"

# ---------------------------------------------------------------------------
# 3. Assemble .app bundle
# ---------------------------------------------------------------------------
APP_BUNDLE="$BUILD_DIR/$BUNDLE_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Process Info.plist — replace __VERSION__ placeholder
sed "s/__VERSION__/$VERSION/g" "$PROJECT_ROOT/SupportFiles/Info.plist" \
    > "$APP_BUNDLE/Contents/Info.plist"

# PkgInfo
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Assembled $APP_BUNDLE"

# ---------------------------------------------------------------------------
# 4. Code-sign (optional — requires DEVELOPER_ID_APPLICATION env var)
# ---------------------------------------------------------------------------
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "==> Signing with identity: $DEVELOPER_ID_APPLICATION"
    codesign --force --deep --timestamp \
        --options runtime \
        --entitlements "$PROJECT_ROOT/SupportFiles/Sideman.entitlements" \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --verbose=2 "$APP_BUNDLE"
else
    echo "==> Skipping code signing (DEVELOPER_ID_APPLICATION not set)"
fi

# ---------------------------------------------------------------------------
# 5. Create DMG
# ---------------------------------------------------------------------------
DMG_NAME="$APP_NAME-v$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"
echo "==> DMG: $DMG_PATH"

# ---------------------------------------------------------------------------
# 6. Notarize (optional — requires Apple ID credentials)
# ---------------------------------------------------------------------------
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_ID_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
else
    echo "==> Skipping notarization (APPLE_ID / APPLE_ID_PASSWORD / APPLE_TEAM_ID not set)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "==> Build complete!"
echo "    App:     $APP_BUNDLE"
echo "    DMG:     $DMG_PATH"
echo "    Version: $VERSION"
