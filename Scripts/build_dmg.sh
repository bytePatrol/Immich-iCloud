#!/bin/bash
set -euo pipefail

# Build DMG for Immich-iCloud
# Usage: ./Scripts/build_dmg.sh [--skip-build] [--skip-tests]
#
# Options:
#   --skip-build   Skip xcodebuild, use existing build artifacts
#   --skip-tests   Skip running tests before building
#
# Output:
#   build/Immich-iCloud-<version>.dmg
#
# Requires:
#   brew install create-dmg
#   xcodegen (for project regeneration)

APP_NAME="Immich-iCloud"
BUILD_DIR="build"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_BUILD=false
SKIP_TESTS=false

cd "$PROJECT_DIR"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        --skip-tests) SKIP_TESTS=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# Check for create-dmg
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

echo "============================================"
echo "  ${APP_NAME} DMG Builder"
echo "============================================"
echo ""

# Step 1: Regenerate Xcode project & resolve dependencies
if [ "$SKIP_BUILD" = false ]; then
    echo "[1/7] Regenerating Xcode project..."
    if command -v xcodegen &> /dev/null; then
        xcodegen generate
        echo "  Project regenerated from project.yml"
    else
        echo "  Warning: xcodegen not found, using existing project"
    fi
    echo ""

    echo "[2/7] Resolving SPM dependencies..."
    xcodebuild -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -resolvePackageDependencies \
        2>&1 | grep -E "(Resolved|Fetching|error:)" || true
    echo "  Dependencies resolved"
    echo ""
else
    echo "[1/7] Skipping project generation (--skip-build)"
    echo "[2/7] Skipping dependency resolution (--skip-build)"
    echo ""
fi

# Step 2: Run tests (unless skipped)
if [ "$SKIP_BUILD" = false ] && [ "$SKIP_TESTS" = false ]; then
    echo "[3/7] Running tests..."
    xcodebuild -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Debug \
        test \
        2>&1 | grep -E "(Test Suite|Test Case|tests|passed|failed|error:)" || true
    echo "  Tests complete"
    echo ""
else
    echo "[3/7] Skipping tests"
    echo ""
fi

# Step 3: Build release
if [ "$SKIP_BUILD" = false ]; then
    echo "[4/7] Building Release configuration..."
    xcodebuild -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}" \
        build \
        2>&1 | grep -E "(Build Succeeded|error:)" || true
    echo ""
else
    echo "[4/7] Skipping build (--skip-build)"
    echo ""
fi

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at ${APP_PATH}"
    echo "Run without --skip-build to build first."
    exit 1
fi

# Step 4: Extract version from built app
echo "[5/7] Extracting version info..."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
echo "  Version: ${VERSION} (build ${BUILD_NUM})"
echo "  DMG:     ${DMG_NAME}"
echo ""

# Step 5: Prepare assets
echo "[6/7] Preparing DMG assets..."
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
BACKGROUND="${PROJECT_DIR}/images/dmg-background.png"
VOL_ICON="${PROJECT_DIR}/images/Immich-iCloud.icns"

# Remove any previous DMG
rm -f "$DMG_PATH"

echo "  Background: ${BACKGROUND}"
echo "  Volume icon: ${VOL_ICON}"
echo ""

# Step 6: Create styled DMG using create-dmg
echo "[7/7] Creating styled DMG..."

# create-dmg flags:
#   --volname: Name shown in Finder title bar
#   --volicon: Icon for the mounted volume
#   --background: Background image (660x400px matching window size)
#   --window-pos: Position on screen when opened
#   --window-size: Window dimensions in points
#   --icon-size: Size of icons in the DMG window
#   --icon: Position the app icon
#   --app-drop-link: Position the Applications alias
#   --no-internet-enable: Skip legacy internet-enable flag
#   --hide-extension: Hide .app extension on the icon

CREATE_DMG_ARGS=(
    --volname "${APP_NAME}"
    --window-pos 200 120
    --window-size 660 400
    --icon-size 128
    --icon "${APP_NAME}.app" 180 170
    --app-drop-link 480 170
    --no-internet-enable
    --hide-extension "${APP_NAME}.app"
)

# Add background if it exists
if [ -f "$BACKGROUND" ]; then
    CREATE_DMG_ARGS+=(--background "$BACKGROUND")
fi

# Add volume icon if it exists
if [ -f "$VOL_ICON" ]; then
    CREATE_DMG_ARGS+=(--volicon "$VOL_ICON")
fi

create-dmg \
    "${CREATE_DMG_ARGS[@]}" \
    "$DMG_PATH" \
    "$APP_PATH"

# Set custom icon on the .dmg file itself
if [ -f "$VOL_ICON" ]; then
    osascript <<APPLESCRIPT
use framework "AppKit"
use scripting additions
set iconImage to current application's NSImage's alloc()'s initWithContentsOfFile:"${VOL_ICON}"
current application's NSWorkspace's sharedWorkspace()'s setIcon:iconImage forFile:"${DMG_PATH}" options:0
APPLESCRIPT
    echo "  DMG file icon set"
else
    echo "  Skipped icon (no .icns file)"
fi

# Report
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "============================================"
echo "  DMG created successfully"
echo "  Path: ${DMG_PATH}"
echo "  Size: ${DMG_SIZE}"
echo "  Version: ${VERSION} (build ${BUILD_NUM})"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Test:     open '${DMG_PATH}'"
echo "  2. Sign:     ./Scripts/sign_and_notarize.sh <developer-id>"
echo "  3. EdDSA:    ./bin/sign_update '${DMG_PATH}'"
echo "  4. Release:  gh release create v${VERSION} '${DMG_PATH}' --title 'v${VERSION}'"
echo "  5. Appcast:  Update appcast.xml with EdDSA signature, push to main"
echo ""
echo "GitHub repo: https://github.com/bytePatrol/Immich-iCloud"
