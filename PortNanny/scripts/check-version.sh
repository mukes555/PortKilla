#!/bin/bash
# Asserts that the version lives in one place: scripts/build.sh VERSION must
# equal the newest "## x.y.z" heading in CHANGELOG.md, and, when a tag is
# given, that tag too. A mismatch once shipped a release whose DMG, notes,
# and update check all disagreed about which version it was.
# Usage: check-version.sh [vX.Y.Z]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SCRIPT_DIR/build.sh")"
CHANGELOG_VERSION="$(grep -m1 -E '^## [0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/CHANGELOG.md" | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"

status=0
if [ "$BUILD_VERSION" != "$CHANGELOG_VERSION" ]; then
    echo "version mismatch: build.sh says $BUILD_VERSION, newest CHANGELOG section is $CHANGELOG_VERSION" >&2
    status=1
fi
if [ "${1:-}" != "" ]; then
    TAG_VERSION="${1#v}"
    if [ "$TAG_VERSION" != "$BUILD_VERSION" ]; then
        echo "version mismatch: tag is $TAG_VERSION, build.sh says $BUILD_VERSION" >&2
        status=1
    fi
fi
if [ "$status" -eq 0 ]; then
    echo "version $BUILD_VERSION: build.sh, CHANGELOG${1:+, tag} agree"
fi
exit "$status"
