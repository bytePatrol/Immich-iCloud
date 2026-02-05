#!/bin/bash
set -euo pipefail

# Bump version numbers for Immich-iCloud
# Usage: ./Scripts/bump_version.sh <new-version> [<new-build>]
#
# Examples:
#   ./Scripts/bump_version.sh 1.1.0        # Sets version to 1.1.0, auto-increments build
#   ./Scripts/bump_version.sh 1.1.0 5      # Sets version to 1.1.0, build 5

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="${PROJECT_DIR}/project.yml"

NEW_VERSION="${1:-}"

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <new-version> [<new-build>]"
    echo ""
    echo "Examples:"
    echo "  $0 1.1.0       # Version 1.1.0, auto-increment build"
    echo "  $0 1.1.0 5     # Version 1.1.0, build 5"
    echo ""
    # Show current version
    CURRENT_VERSION=$(grep "MARKETING_VERSION:" "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION:" "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    echo "Current: ${CURRENT_VERSION} (build ${CURRENT_BUILD})"
    exit 1
fi

# Get current build number for auto-increment
CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION:" "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
NEW_BUILD="${2:-$((CURRENT_BUILD + 1))}"

echo "Bumping version:"
echo "  Version: ${NEW_VERSION}"
echo "  Build:   ${NEW_BUILD}"
echo ""

cd "$PROJECT_DIR"

# Update project.yml
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_YML"
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"

echo "Updated project.yml"

# Regenerate Xcode project
if command -v xcodegen &> /dev/null; then
    xcodegen generate > /dev/null 2>&1
    echo "Regenerated Xcode project"
fi

echo ""
echo "Done! Version is now ${NEW_VERSION} (build ${NEW_BUILD})"
