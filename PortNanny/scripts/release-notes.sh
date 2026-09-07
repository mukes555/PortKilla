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
# The heading must be exactly this version ("## 1.1" must not match 1.13.0).
SECTION="$(awk -v ver="$VERSION" '
    BEGIN { gsub(/\./, "\\.", ver) }
    $0 ~ "^## " ver "([^0-9.]|$)" { capture=1; next }
    capture && /^## / { exit }
    capture { print }
' "$CHANGELOG")"

# Trim leading/trailing blank lines.
SECTION="$(printf '%s\n' "$SECTION" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$SECTION" ]; then
    # Fail the release rather than publish one with no notes: it means the
    # "[Unreleased]" section was never renamed.
    echo "release-notes.sh: no '## $VERSION' section in CHANGELOG.md" >&2
    exit 1
fi

cat <<EOF
## What's new in v${VERSION}
${SECTION}

---

## 📦 Install

Download **PortNanny-${VERSION}.dmg** below, open it, and drag PortNanny to
Applications. Universal binary: runs natively on Apple Silicon and Intel;
requires macOS 13 (Ventura) or newer.

> Not notarized (no Apple Developer account). First launch on macOS 15 or
> newer: open it once, then System Settings → Privacy & Security → **Open
> Anyway**. On macOS 13 and 14: right-click PortNanny.app → **Open** → **Open**.
> Either way, \`xattr -dr com.apple.quarantine /Applications/PortNanny.app\`
> skips the dialog. Homebrew (\`brew install --cask portnanny\`) does this for you.
EOF
