#!/bin/bash
# Builds the GitHub Release body for a version, from CHANGELOG.md.
# Usage: release-notes.sh <version>   e.g. release-notes.sh 1.6.0
# Prints the release notes to stdout. Used by .github/workflows/release.yml.

set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

# Pull the section for this version: everything between "## <version>" and the
# next "## " heading.
SECTION="$(awk -v ver="$VERSION" '
    $0 ~ "^## " ver { capture=1; next }
    capture && /^## / { exit }
    capture { print }
' "$CHANGELOG")"

# Trim leading/trailing blank lines.
SECTION="$(printf '%s\n' "$SECTION" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$SECTION" ]; then
    SECTION="See the [changelog](https://github.com/mukes555/PortKilla/blob/main/CHANGELOG.md)."
fi

cat <<EOF
## ⚡ What's new in v${VERSION}
${SECTION}

---

## 📦 Install

Download **PortKilla-${VERSION}.dmg** below, open it, and drag PortKilla to
Applications. Universal binary — runs natively on Apple Silicon and Intel;
requires macOS 13 (Ventura) or newer.

> Not notarized (no Apple Developer account): on first launch, right-click
> PortKilla.app → **Open** → **Open**, or run
> \`xattr -dr com.apple.quarantine /Applications/PortKilla.app\`.
EOF
