#!/bin/zsh
set -euo pipefail

# Builds a download-and-install package: prebuilt VOCR.app (with the bundled CLI),
# the Finder Quick Action installer, and a double-clickable Install.command.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/.release"
VERSION="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' "$ROOT/Sources/AppleVisionOCRCLI/CommandRunner.swift")"

"$ROOT/scripts/package-vocr-app.sh"

APP="$ROOT/.workflow_build/VOCR.app"
ARCH="$(lipo -archs "$APP/Contents/MacOS/VOCR" | tr ' ' '-')"
NAME="VOCR-$VERSION-macos-$ARCH"
STAGE="$OUT_DIR/$NAME"

rm -rf "$STAGE" "$OUT_DIR/$NAME.zip" "$OUT_DIR/$NAME.zip.sha256"
mkdir -p "$STAGE"

cp -R "$APP" "$STAGE/VOCR.app"
cp "$ROOT/scripts/install-vocr-quick-action.sh" \
  "$ROOT/scripts/vocr-finder-action.sh" \
  "$ROOT/scripts/apple-vision-ocr-finder-action.sh" \
  "$ROOT/LICENSE" \
  "$STAGE/"

cat > "$STAGE/Install.command" <<'EOF'
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
./install-vocr-quick-action.sh
echo
echo "설치 완료. Finder에서 PDF를 선택하고 우클릭 > 빠른 동작 > Apple Vision OCR을 실행하세요."
echo "Installed. In Finder, select PDFs, right-click, then Quick Actions > Apple Vision OCR."
read -k 1 "?아무 키나 누르면 창을 닫습니다 / Press any key to close."
EOF

cat > "$STAGE/README.txt" <<EOF
VOCR $VERSION (Apple Vision OCR) - macOS $ARCH

요구 사항 / Requirements
- macOS 13 이상, Apple Silicon Mac (arm64)
- 빌드 도구(Xcode)는 필요 없습니다. / No Xcode or Swift toolchain needed.

설치 / Install
1. Install.command 를 더블클릭합니다. / Double-click Install.command.
2. macOS가 열기를 막으면 시스템 설정 > 개인정보 보호 및 보안에서 "그래도 열기"를 누른 뒤 다시 실행합니다.
   If macOS blocks it, open System Settings > Privacy & Security, click "Open Anyway", then run it again.
   가장 확실한 방법(터미널) / Most reliable (Terminal):
     xattr -dr com.apple.quarantine "<이 폴더 / this folder>"
     "<이 폴더 / this folder>/install-vocr-quick-action.sh"

설치 위치 / Installed files
  ~/Applications/VOCR.app
  ~/.local/bin/apple-vision-ocr
  ~/.local/bin/vocr-finder-action
  ~/.local/bin/apple-vision-ocr-finder-action
  ~/Library/Services/Apple Vision OCR.workflow
경로 변경 / Custom paths: VOCR_APP_INSTALL_DIR, VOCR_BIN_DIR 환경변수

사용 / Use
Finder에서 PDF를 선택 > 우클릭 > 빠른 동작 > Apple Vision OCR
CLI: ~/.local/bin/apple-vision-ocr input.pdf --help

제거 / Uninstall
  rm -rf ~/Applications/VOCR.app ~/Library/Services/"Apple Vision OCR.workflow"
  rm -f ~/.local/bin/apple-vision-ocr ~/.local/bin/vocr-finder-action ~/.local/bin/apple-vision-ocr-finder-action

앱은 ad-hoc 서명이며 Apple 공증(notarization)을 받지 않았습니다. 설치 스크립트가 설치된 복사본의
격리(quarantine) 속성을 제거합니다. / The app is ad-hoc signed and not notarized; the installer
removes the quarantine attribute from the installed copy.
Source: https://github.com/jangisaac-dev/apple-vision-ocr-cli
EOF

chmod 755 "$STAGE/Install.command" "$STAGE"/*.sh

(cd "$OUT_DIR" && ditto -c -k --norsrc --noextattr --noqtn --keepParent "$NAME" "$NAME.zip" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
echo "$OUT_DIR/$NAME.zip"
