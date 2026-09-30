#!/bin/sh
# Unsaid installer: puts Unsaid.app in ~/Applications and opens it.
#
#   curl -fsSL https://moizahmedd.github.io/unsaid/install | sh
#
# No sudo. Checks the zip's SHA-256 against the release's SHA256SUMS before installing.
# UNSAID_VERSION=0.1.0 installs a specific release instead of the latest. Run it again to update.
set -eu

REPO="MoizAhmedd/unsaid"
if [ -n "${UNSAID_VERSION:-}" ]; then
  BASE="https://github.com/$REPO/releases/download/v${UNSAID_VERSION#v}"
else
  BASE="https://github.com/$REPO/releases/latest/download"
fi
DEST="$HOME/Applications"

[ "$(uname)" = Darwin ] || { echo "Unsaid is for macOS."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || { echo "Unsaid needs macOS 13 or later."; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Unsaid…"
curl -fsSL "$BASE/Unsaid.zip" -o "$tmp/Unsaid.zip"
curl -fsSL "$BASE/SHA256SUMS" -o "$tmp/SHA256SUMS"
(cd "$tmp" && grep ' Unsaid.zip$' SHA256SUMS | shasum -a 256 -c -) >/dev/null \
  || { echo "Checksum mismatch; nothing was installed."; exit 1; }

mkdir -p "$DEST"
osascript -e 'quit app id "dev.unsaid.app"' >/dev/null 2>&1 || true
rm -rf "$DEST/Unsaid.app"
ditto -x -k "$tmp/Unsaid.zip" "$DEST"
# curl doesn't set the quarantine flag; clear it anyway in case a proxy or tool did.
xattr -dr com.apple.quarantine "$DEST/Unsaid.app" 2>/dev/null || true
echo "Installed $DEST/Unsaid.app"
open "$DEST/Unsaid.app"
echo "Unsaid is in your menu bar."
