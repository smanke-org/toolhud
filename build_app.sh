#!/bin/bash
# Assembles and signs ToolHUD.app: Developer ID, hardened runtime, not sandboxed
# (it watches the mouse system-wide, presses keys for its buttons and draws over every app).
#
#   ./build_app.sh [signing identity]
set -euo pipefail

APP_NAME="ToolHUD"
BUNDLE_ID="com.smanke.ToolHUD"
ROOT="$(cd "$(dirname "$0")" && pwd)"

IDENTITY="${1:-}"
BUILD_PATH="$ROOT/.build"
ENTITLEMENTS="$ROOT/Resources/ToolHUD.entitlements"
BUILD="$ROOT/.build/app"
APP="$BUILD/$APP_NAME.app"
SWIFT_ARGS=(-c release --arch arm64 --arch x86_64 --build-path "$BUILD_PATH")

echo "==> Building universal binary"
swift build "${SWIFT_ARGS[@]}"

# Ask SwiftPM where it put the binary rather than assuming: the location has moved
# between toolchains, and a hardcoded path once packaged a days-old binary inside a
# freshly versioned bundle. Then refuse to package it if any source is newer.
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
if [ ! -x "$BIN_DIR/$APP_NAME" ]; then
  echo "No built binary at $BIN_DIR/$APP_NAME." >&2
  exit 1
fi
NEWER_SOURCE=$(find "$ROOT/Sources" "$ROOT/Package.swift" -newer "$BIN_DIR/$APP_NAME" -type f -print -quit)
if [ -n "$NEWER_SOURCE" ]; then
  echo "$BIN_DIR/$APP_NAME is older than $NEWER_SOURCE — refusing to package a stale binary." >&2
  exit 1
fi
echo "    using $BIN_DIR"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# The Shortcuts app's actions (ShortcutsIntents.swift). SwiftPM compiles the constant
# values App Intents needs but doesn't extract the metadata, so run Xcode's extractor here.
echo "==> Extracting App Intents metadata"
INTENTS_WORK="$BUILD_PATH/appintents"
rm -rf "$INTENTS_WORK"
mkdir -p "$INTENTS_WORK/out"
ls "$ROOT"/Sources/ToolHUD/*.swift > "$INTENTS_WORK/sources.txt"
find "$BUILD_PATH" -path "*Release/ToolHUD-p.build/Objects-normal/arm64/*" -name "*.swiftconstvalues" \
  -newer "$ROOT/Package.swift" > "$INTENTS_WORK/consts.txt"
if [ ! -s "$INTENTS_WORK/consts.txt" ]; then
  echo "No constant values from the release build; can't extract App Intents metadata." >&2
  exit 1
fi
xcrun appintentsmetadataprocessor --output "$INTENTS_WORK/out" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" \
  --module-name "$APP_NAME" --sdk-root "$(xcrun --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS --deployment-target 26.0 --target-triple arm64-apple-macos26.0 \
  --source-file-list "$INTENTS_WORK/sources.txt" --swift-const-vals-list "$INTENTS_WORK/consts.txt" --quiet-warnings
if ! grep -q ShowHUDIntent "$INTENTS_WORK/out/Metadata.appintents/extract.actionsdata"; then
  echo "App Intents metadata is missing ToolHUD's actions." >&2
  exit 1
fi
cp -R "$INTENTS_WORK/out/Metadata.appintents" "$APP/Contents/Resources/Metadata.appintents"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "==> Resolving signing identity"
if [ -z "$IDENTITY" ]; then
  FOUND=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
  if [ -z "$FOUND" ]; then
    echo "No Developer ID Application identity found in the keychain." >&2
    exit 1
  fi
  IDENTITY=$(echo "$FOUND" | sed -E 's/.*"(.*)"$/\1/')
fi
echo "    $IDENTITY"

echo "==> Signing"
# Keep the .entitlements files free of XML comments: plutil accepts them, but codesign's
# AMFI parser rejects the file ("syntax error near line 5").
codesign --force --options runtime --timestamp \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "Built $APP ($VERSION)"
