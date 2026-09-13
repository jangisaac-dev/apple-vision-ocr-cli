#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.workflow_build"
APP_DIR="$BUILD_DIR/VOCR.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export SWIFTPM_HOME="$ROOT/.build/swiftpm-home"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"

cd "$ROOT"

swift build -c release --product VOCR
swift build -c release --product apple-vision-ocr

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT/.build/release/VOCR" "$MACOS_DIR/VOCR"
chmod 755 "$MACOS_DIR/VOCR"
cp "$ROOT/.build/release/apple-vision-ocr" "$MACOS_DIR/apple-vision-ocr"
chmod 755 "$MACOS_DIR/apple-vision-ocr"
cp "$ROOT/assets/icon/VOCR.icns" "$RESOURCES_DIR/VOCR.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>CFBundleExecutable</key>
  <string>VOCR</string>
  <key>CFBundleIdentifier</key>
  <string>dev.oth.vocr</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>VOCR</string>
  <key>CFBundleDisplayName</key>
  <string>VOCR</string>
  <key>CFBundleIconFile</key>
  <string>VOCR</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.2.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
