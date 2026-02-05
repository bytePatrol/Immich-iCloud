#!/bin/bash
set -euo pipefail

# Sign and notarize Immich-iCloud
# Usage: ./Scripts/sign_and_notarize.sh <developer-id> [<apple-id> <team-id>]
#
# Prerequisites:
#   - Valid Apple Developer account
#   - Developer ID Application certificate installed in Keychain
#   - App-specific password stored in Keychain:
#     xcrun notarytool store-credentials "notarytool-profile" \
#       --apple-id "you@example.com" \
#       --team-id "TEAMID" \
#       --password "app-specific-password"
#
# Examples:
#   # Using credentials profile (recommended):
#   ./Scripts/sign_and_notarize.sh "Developer ID Application: Your Name (TEAMID)"
#
#   # Using explicit credentials:
#   ./Scripts/sign_and_notarize.sh "Developer ID Application: Your Name (TEAMID)" "you@example.com" "TEAMID"

APP_NAME="Immich-iCloud"
BUILD_DIR="build"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"

DEVELOPER_ID="${1:-}"

if [ -z "$DEVELOPER_ID" ]; then
    echo "Usage: $0 <developer-id> [<apple-id> <team-id>]"
    echo ""
    echo "Arguments:"
    echo "  developer-id   Signing identity (e.g., 'Developer ID Application: Name (TEAMID)')"
    echo "  apple-id       Apple ID email (optional if using stored credentials)"
    echo "  team-id        Team ID (optional if using stored credentials)"
    echo ""
    echo "Set up stored credentials first:"
    echo "  xcrun notarytool store-credentials 'notarytool-profile' \\"
    echo "    --apple-id 'you@example.com' --team-id 'TEAMID'"
    exit 1
fi

APPLE_ID="${2:-}"
TEAM_ID="${3:-}"

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at ${APP_PATH}"
    echo "Run ./Scripts/build_dmg.sh first."
    exit 1
fi

# Extract version for DMG name
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "============================================"
echo "  ${APP_NAME} Sign & Notarize"
echo "  Version: ${VERSION}"
echo "============================================"
echo ""

# Step 1: Sign embedded Sparkle framework and XPC services
SPARKLE_FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "[1/6] Signing embedded Sparkle framework..."

    # Sign XPC services inside Sparkle (innermost first)
    INSTALLER_XPC="${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc"
    if [ -d "$INSTALLER_XPC" ]; then
        codesign --force --sign "$DEVELOPER_ID" --options runtime "$INSTALLER_XPC"
        echo "  Signed Installer.xpc"
    fi

    DOWNLOADER_XPC="${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc"
    if [ -d "$DOWNLOADER_XPC" ]; then
        codesign --force --sign "$DEVELOPER_ID" --options runtime "$DOWNLOADER_XPC"
        echo "  Signed Downloader.xpc"
    fi

    # Sign Autoupdate helper
    AUTOUPDATE="${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate"
    if [ -f "$AUTOUPDATE" ]; then
        codesign --force --sign "$DEVELOPER_ID" --options runtime "$AUTOUPDATE"
        echo "  Signed Autoupdate"
    fi

    # Sign the Sparkle framework itself
    codesign --force --sign "$DEVELOPER_ID" --options runtime "$SPARKLE_FRAMEWORK"
    echo "  Signed Sparkle.framework"
    echo ""
else
    echo "[1/6] No embedded Sparkle framework found, skipping"
    echo ""
fi

# Step 2: Sign the app bundle
echo "[2/6] Signing app bundle..."
codesign --force --deep --sign "$DEVELOPER_ID" \
    --options runtime \
    --entitlements "${APP_NAME}/${APP_NAME}.entitlements" \
    "$APP_PATH"
echo "  Signed with: ${DEVELOPER_ID}"

# Step 3: Verify signature
echo "[3/6] Verifying signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "  Signature valid."

# Step 4: Rebuild DMG with signed app
echo "[4/6] Rebuilding DMG with signed app..."
if [ -f "$DMG_PATH" ]; then
    # Re-run build_dmg with --skip-build to package the now-signed app
    ./Scripts/build_dmg.sh --skip-build --skip-tests
    echo "  DMG rebuilt with signed app"
else
    echo "  Warning: DMG not found at ${DMG_PATH}"
    echo "  Run ./Scripts/build_dmg.sh first, then re-run this script."
    exit 1
fi

# Step 5: Notarize
echo "[5/6] Submitting for notarization..."
if [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ]; then
    # Use explicit credentials
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --wait
else
    # Use stored credentials profile
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "notarytool-profile" \
        --wait
fi

# Step 6: Staple
echo "[6/6] Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "============================================"
echo "  Notarization complete!"
echo "  DMG: ${DMG_PATH}"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Generate EdDSA signature: ./bin/sign_update '${DMG_PATH}'"
echo "  2. Update Scripts/appcast-template.xml with the signature"
echo "  3. Upload DMG and appcast to your hosting"
