# AI Install And Setup Guide

This guide is for coding agents, automation scripts, and CI-like local checks
that need to install, verify, or package Apple Vision OCR without guessing.

## Project Boundary

Work inside the repository checkout:

```bash
git clone https://github.com/jangisaac-dev/apple-vision-ocr-cli.git
cd apple-vision-ocr-cli
```

Do not write generated files into global locations when a project-local path is
enough. Do not commit `.build/`, `.workflow_build/`, `.omx/`, `.env*`, logs, or
`.DS_Store` files.

## Requirements

- macOS 13 or later.
- Xcode command line tools or Xcode.
- Swift 5.9 or later.
- Apple Vision framework availability on the host Mac.

Check the local toolchain:

```bash
swift --version
xcode-select -p
```

## Build And Test

Use project-local SwiftPM cache/module paths:

```bash
env SWIFTPM_HOME=.build/swiftpm-home \
  CLANG_MODULE_CACHE_PATH=.build/module-cache \
  swift build
```

Run tests:

```bash
env SWIFTPM_HOME=.build/swiftpm-home \
  CLANG_MODULE_CACHE_PATH=.build/module-cache \
  swift test
```

Validate the installer script syntax:

```bash
zsh -n scripts/install-vocr-quick-action.sh
```

## Package The CLI And App

Create the release binary and app bundle:

```bash
scripts/package-vocr-app.sh
```

Expected output artifact:

```text
.workflow_build/VOCR.app
```

Validate the app bundle:

```bash
codesign --verify --deep --strict .workflow_build/VOCR.app
plutil -lint .workflow_build/VOCR.app/Contents/Info.plist
```

## Sandbox Note

SwiftPM release packaging and Apple Vision OCR may fail inside restricted
sandboxes with errors such as:

```text
sandbox-exec: sandbox_apply: Operation not permitted
Foundation._GenericObjCError
```

When that happens, do not rewrite the code based only on the sandbox failure.
Rerun the same packaging or OCR smoke command outside the sandbox after getting
the required user approval.

## OCR Smoke Test

After packaging, run the release binary against the included fixture:

```bash
mkdir -p .build/public-smoke
.build/release/apple-vision-ocr Samples/sample.pdf \
  --txt-only \
  --txt-output .build/public-smoke/sample.txt \
  --page-breaks
```

Expected text:

```text
===== Page 1 =====

HELLO OCR SAMPLE
APPLE VISION TEXT
COPYABLE AFTER OCR
```

Clean up the smoke output before finishing:

```bash
rm -rf .build/public-smoke
```

## Real User Install

The user-level installer builds the app and writes these default paths:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

Run it only when installing for the current macOS user:

```bash
scripts/install-vocr-quick-action.sh
```

Custom app and binary locations:

```bash
VOCR_APP_INSTALL_DIR="$HOME/Applications" \
VOCR_BIN_DIR="$HOME/.local/bin" \
scripts/install-vocr-quick-action.sh
```

The Finder workflow is always installed under the current user's
`~/Library/Services`.

## Isolated Installer Verification

To verify installer behavior without touching the real user Library, run with a
project-local fake `HOME`:

```bash
env HOME="$PWD/.build/install-smoke/home" \
  VOCR_APP_INSTALL_DIR="$PWD/.build/install-smoke/home/Applications" \
  VOCR_BIN_DIR="$PWD/.build/install-smoke/home/bin" \
  scripts/install-vocr-quick-action.sh
```

Validate generated workflow plists:

```bash
plutil -lint \
  ".build/install-smoke/home/Library/Services/Apple Vision OCR.workflow/Contents/Info.plist" \
  ".build/install-smoke/home/Library/Services/Apple Vision OCR.workflow/Contents/document.wflow" \
  ".build/install-smoke/home/Library/Services/Apple Vision OCR.workflow/Contents/version.plist"
```

Confirm the workflow points to the custom binary path:

```bash
rg -n "vocr-finder-action|\\.local/bin" \
  ".build/install-smoke/home/Library/Services/Apple Vision OCR.workflow/Contents/document.wflow"
```

Clean up:

```bash
rm -rf .build/install-smoke
```

## Privacy And Release Checks

Before pushing or tagging a release, inspect the committed surface:

```bash
git status --ignored --short
git diff --check
git grep -n -I -E '(ghp_|github_pat_|sk-[A-Za-z0-9]{20,}|BEGIN (RSA |OPENSSH |DSA |EC |PGP )?PRIVATE KEY|Authorization:|Bearer [A-Za-z0-9._~+/-]{20,}|api[_-]?key|secret|password)'
```

Check history metadata and tracked history for personal data:

```bash
git log --all --format='%H%x09%an <%ae>%x09%cn <%ce>%x09%s%x09%b'
git rev-list --all | xargs git grep -n -I -E '(gmail\\.com|/Users/|ghp_|github_pat_|sk-[A-Za-z0-9]{20,}|BEGIN (RSA |OPENSSH |DSA |EC |PGP )?PRIVATE KEY)'
```

Expected release author identity:

```text
jangisaac-dev <78341411+jangisaac-dev@users.noreply.github.com>
```

## Process Cleanup

Before reporting completion, verify no task-created long-running processes are
left behind:

```bash
pgrep -fl "VOCR|apple-vision-ocr|swift-build|swiftc|git remote-https|git-remote-https"
```

If a process appears, only stop it when it was started by the current task. Do
not kill unrelated user processes.

## Release Checklist

1. Bump `CommandRunner.version` and `CFBundleShortVersionString` / `CFBundleVersion` in `scripts/package-vocr-app.sh`.
2. `swift test` passes.
3. `scripts/make-release-package.sh` passes (it runs `scripts/package-vocr-app.sh`) and writes
   `.release/VOCR-<version>-macos-<arch>.zip` plus `.zip.sha256`.
4. `codesign` and `plutil` checks pass.
5. Sample OCR smoke passes outside restricted sandboxes when needed.
6. Install from the unzipped package into a fake `HOME` (see Isolated Installer Verification; run the
   package's `install-vocr-quick-action.sh` instead of the checkout's) and confirm it does not build.
7. Privacy scans do not show secrets or personal metadata.
8. `README.md`, `docs/user-guide.md`, and this guide are current.
9. Tag `v<version>` points at the release commit; the GitHub Release has the zip and its SHA-256.
