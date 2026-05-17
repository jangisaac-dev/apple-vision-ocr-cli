#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_INSTALL_DIR="${VOCR_APP_INSTALL_DIR:-$HOME/Applications}"
BIN_DIR="${VOCR_BIN_DIR:-$HOME/.local/bin}"
WORKFLOW="$HOME/Library/Services/Apple Vision OCR.workflow"
WORKFLOW_CONTENTS="$WORKFLOW/Contents"

"$ROOT/scripts/package-vocr-app.sh"

mkdir -p "$APP_INSTALL_DIR" "$BIN_DIR" "$HOME/Library/Services"

rm -rf "$APP_INSTALL_DIR/VOCR.app"
cp -R "$ROOT/.workflow_build/VOCR.app" "$APP_INSTALL_DIR/VOCR.app"

cp "$ROOT/.build/release/apple-vision-ocr" "$BIN_DIR/apple-vision-ocr"
cp "$ROOT/scripts/vocr-finder-action.sh" "$BIN_DIR/vocr-finder-action"
cp "$ROOT/scripts/apple-vision-ocr-finder-action.sh" "$BIN_DIR/apple-vision-ocr-finder-action"
chmod 755 "$BIN_DIR/apple-vision-ocr" "$BIN_DIR/vocr-finder-action" "$BIN_DIR/apple-vision-ocr-finder-action"

rm -rf "$WORKFLOW"
mkdir -p "$WORKFLOW_CONTENTS"

cat > "$WORKFLOW_CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSBackgroundColorName</key>
      <string>background</string>
      <key>NSIconName</key>
      <string>NSActionTemplate</string>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>Apple Vision OCR</string>
      </dict>
      <key>NSMessage</key>
      <string>runWorkflowAsService</string>
      <key>NSRequiredContext</key>
      <dict>
        <key>NSApplicationIdentifier</key>
        <string>com.apple.finder</string>
      </dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>com.adobe.pdf</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

cat > "$WORKFLOW_CONTENTS/document.wflow" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AMApplicationBuild</key>
  <string>533</string>
  <key>AMApplicationVersion</key>
  <string>2.10</string>
  <key>AMDocumentVersion</key>
  <string>2</string>
  <key>actions</key>
  <array>
    <dict>
      <key>action</key>
      <dict>
        <key>ActionBundlePath</key>
        <string>/System/Library/Automator/Run Shell Script.action</string>
        <key>ActionName</key>
        <string>Run Shell Script</string>
        <key>ActionParameters</key>
        <dict>
          <key>CheckedForUserDefaultShell</key>
          <true/>
          <key>COMMAND_STRING</key>
          <string>#!/bin/zsh
exec "$HOME/.local/bin/vocr-finder-action" "$@"</string>
          <key>inputMethod</key>
          <integer>1</integer>
          <key>shell</key>
          <string>/bin/zsh</string>
          <key>source</key>
          <string></string>
        </dict>
        <key>AMAccepts</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Optional</key>
          <true/>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.string</string>
          </array>
        </dict>
        <key>AMActionVersion</key>
        <string>2.0.3</string>
        <key>AMApplication</key>
        <array>
          <string>Automator</string>
        </array>
        <key>AMProvides</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.string</string>
          </array>
        </dict>
        <key>BundleIdentifier</key>
        <string>com.apple.RunShellScript</string>
        <key>CanShowSelectedItemsWhenRun</key>
        <false/>
        <key>CanShowWhenRun</key>
        <true/>
        <key>CFBundleVersion</key>
        <string>2.0.3</string>
        <key>Class Name</key>
        <string>RunShellScriptAction</string>
        <key>InputUUID</key>
        <string>C97FB42F-AF4B-4FDA-8E0C-61E62246D0B4</string>
        <key>OutputUUID</key>
        <string>33B38493-AE8E-41A9-AB97-A625A0F900A8</string>
        <key>UUID</key>
        <string>1DDF8E80-36D1-4005-8CCD-571DE01D1226</string>
        <key>isViewVisible</key>
        <integer>1</integer>
      </dict>
      <key>isViewVisible</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>connectors</key>
  <dict/>
  <key>workflowMetaData</key>
  <dict>
    <key>applicationBundleID</key>
    <string>com.apple.finder</string>
    <key>applicationPath</key>
    <string>/System/Library/CoreServices/Finder.app</string>
    <key>inputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject.PDF</string>
    <key>outputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>presentationMode</key>
    <integer>15</integer>
    <key>processesInput</key>
    <false/>
    <key>serviceApplicationBundleID</key>
    <string>com.apple.finder</string>
    <key>serviceApplicationPath</key>
    <string>/System/Library/CoreServices/Finder.app</string>
    <key>serviceInputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject.PDF</string>
    <key>serviceOutputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>serviceProcessesInput</key>
    <false/>
    <key>systemImageName</key>
    <string>doc.text.magnifyingglass</string>
    <key>useAutomaticInputType</key>
    <false/>
    <key>workflowTypeIdentifier</key>
    <string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict>
</plist>
PLIST

cat > "$WORKFLOW_CONTENTS/version.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>BuildVersion</key>
  <string>533</string>
  <key>ProjectName</key>
  <string>Automator</string>
  <key>SourceVersion</key>
  <string>533000000000000</string>
</dict>
</plist>
PLIST

touch "$WORKFLOW"

echo "Installed app: $APP_INSTALL_DIR/VOCR.app"
echo "Installed CLI: $BIN_DIR/apple-vision-ocr"
echo "Installed Finder wrapper: $BIN_DIR/vocr-finder-action"
echo "Installed Quick Action: $WORKFLOW"
