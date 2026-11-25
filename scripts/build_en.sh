#!/bin/bash
# Builds the English UI edition of AntigravityProxyLauncher for Apple Silicon (arm64)
# from this source tree, and signs the bundle ad hoc.
# Output: build_output/en/AntigravityProxyLauncher.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build_output/en"
APP="$OUT/AntigravityProxyLauncher.app"

command -v xcodegen >/dev/null || { echo "error: xcodegen is required (brew install xcodegen)" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/int"

echo "[1/4] libAntigravityTun.dylib"
xcodebuild -project "$ROOT/AntigravityTun/AntigravityTun.xcodeproj" -scheme AntigravityTun \
  -configuration Release -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SYMROOT="$OUT/int/dylib" build > "$OUT/dylib.log" 2>&1

echo "[2/4] mitm_proxy"
(cd "$ROOT/tools/mitm_proxy" && GOOS=darwin GOARCH=arm64 go build -trimpath -o "$OUT/int/mitm_proxy" .)

echo "[3/4] launcher"
(cd "$ROOT/launcher" && xcodegen generate > "$OUT/xcodegen.log" 2>&1)
xcodebuild -project "$ROOT/launcher/AntigravityProxyLauncher.xcodeproj" -scheme AntigravityProxyLauncher \
  -configuration Release -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CONFIGURATION_BUILD_DIR="$OUT/int/app" build > "$OUT/app.log" 2>&1

echo "[4/4] bundle and sign"
mv "$OUT/int/app/AntigravityProxyLauncher.app" "$APP"
cp "$OUT/int/dylib/Release/libAntigravityTun.dylib" "$OUT/int/mitm_proxy" "$APP/Contents/Resources/"
[ ! -f "$ROOT/tools/mitm_proxy/.env" ] || cp "$ROOT/tools/mitm_proxy/.env" "$APP/Contents/Resources/.env"
codesign --force --deep --sign - "$APP" 2>&1 | tail -1
codesign --verify --deep --strict "$APP"

echo "Done: $APP"
