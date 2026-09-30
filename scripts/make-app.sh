#!/bin/bash
# Builds Unsaid.app with SwiftPM (Xcode or the Command Line Tools; no .xcodeproj).
#
#   scripts/make-app.sh                      release build for this Mac's architecture, ad-hoc signed,
#                                            → .build/app/Unsaid.app
#   scripts/make-app.sh --debug              debug build
#   scripts/make-app.sh --universal          arm64 + x86_64 (needs full Xcode)
#   scripts/make-app.sh --sign "IDENTITY"    sign with a certificate (SHA-1 or name) instead of ad-hoc
#   scripts/make-app.sh --out DIR            put the app in DIR
#   scripts/make-app.sh --version 0.1.0 --build 42
set -euo pipefail
cd "$(dirname "$0")/.."

CONF=release; UNIVERSAL=0; IDENTITY="-"; OUT=".build/app"; VERSION="0.1.0-dev"; BUILD="1"
while [ $# -gt 0 ]; do
  case "$1" in
    --debug) CONF=debug ;;
    --universal) UNIVERSAL=1 ;;
    --sign) IDENTITY="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    --version) VERSION="$2"; shift ;;
    --build) BUILD="$2"; shift ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
  shift
done

# Universal: each architecture is built on its own and joined with lipo (SwiftPM's combined
# `--arch arm64 --arch x86_64` build goes through xcbuild, which is slower and fussier).
if [ $UNIVERSAL = 1 ]; then
  swift build -c "$CONF" --arch arm64 --product UnsaidApp
  swift build -c "$CONF" --arch x86_64 --product UnsaidApp
  BIN=$(mktemp -d)
  lipo -create "$(swift build -c "$CONF" --arch arm64 --show-bin-path)/UnsaidApp" \
               "$(swift build -c "$CONF" --arch x86_64 --show-bin-path)/UnsaidApp" -output "$BIN/UnsaidApp"
  # lipo drops the linker's ad-hoc signature; put it back so the binary runs (real signing is below).
  codesign --force -s - "$BIN/UnsaidApp"
else
  swift build -c "$CONF" --product UnsaidApp
  BIN=$(swift build -c "$CONF" --show-bin-path)
fi

APP="$OUT/Unsaid.app"
C="$APP/Contents"
rm -rf "$APP"
mkdir -p "$C/MacOS" "$C/Resources"
cp "$BIN/UnsaidApp" "$C/MacOS/Unsaid"
sed -e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD|" Resources/App/Info.plist > "$C/Info.plist"
plutil -lint "$C/Info.plist" >/dev/null

# The icon is drawn by the app itself (Sources/UnsaidApp/Art.swift).
ICONSET=$(mktemp -d)/AppIcon.iconset
"$C/MacOS/Unsaid" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$C/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# No hardened runtime and no timestamp (self-signed and ad-hoc identities have no timestamp server).
echo "==> codesign ($([ "$IDENTITY" = - ] && echo ad-hoc || echo "$IDENTITY"))"
codesign --force --timestamp=none -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "==> $APP"
codesign -d -r- "$APP" 2>&1 | grep designated
