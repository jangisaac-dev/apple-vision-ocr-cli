# AI Agent Install And Usage Guide

This guide is for coding agents, automation scripts, and CI-like local checks
that need to install, run, verify, or package Apple Vision OCR without guessing.

## Quick Start For Agents

Download the prebuilt release, verify the checksum, remove quarantine, install, and run OCR.
The commands pin `v1.3.0`; check the latest tag first with
`gh release view --repo jangisaac-dev/apple-vision-ocr-cli --json tagName --jq .tagName`.

```bash
# Stops at the first failed step (download, checksum, install). The subshell keeps your shell open.
(
  set -euo pipefail
  V=1.3.0
  BASE="https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/download/v$V"
  curl -fLO "$BASE/VOCR-$V-macos-arm64.zip"
  curl -fLO "$BASE/VOCR-$V-macos-arm64.zip.sha256"
  shasum -a 256 -c "VOCR-$V-macos-arm64.zip.sha256"
  unzip -oq "VOCR-$V-macos-arm64.zip"
  xattr -dr com.apple.quarantine "VOCR-$V-macos-arm64"
  "VOCR-$V-macos-arm64/install-vocr-quick-action.sh"
  "$HOME/.local/bin/apple-vision-ocr" --version
)
"$HOME/.local/bin/apple-vision-ocr" input.pdf --txt-only
```

> **Note:** Agents must run `install-vocr-quick-action.sh` directly (non-interactive, needs no Xcode when `VOCR.app` sits next to it). Do NOT run `Install.command`: it waits for an interactive key press.

Portable use without installing (writes nothing to `~/Library` or `~/.local/bin`):
Run `VOCR-1.3.0-macos-arm64/VOCR.app/Contents/MacOS/apple-vision-ocr` by absolute path.
`--split-workers` and all other options work directly from there.

## Choose An Install Path

| Install Path | Requirements | What Gets Written | When To Use |
| :--- | :--- | :--- | :--- |
| **Prebuilt Install** | macOS 13+, Apple Silicon (arm64) | `~/Applications/VOCR.app`<br>`~/.local/bin/apple-vision-ocr`<br>`~/.local/bin/vocr-finder-action`<br>`~/.local/bin/apple-vision-ocr-finder-action`<br>`~/Library/Services/Apple Vision OCR.workflow` | Standard agent setup where persistent CLI access and Finder Quick Action are desired. |
| **Portable (No Install)** | macOS 13+, Apple Silicon (arm64) | Nothing outside the unzipped directory (writes nothing to `~/Library` or `~/.local/bin`) | Ephemeral agents, throwaway containers, CI workers, or when avoiding system changes. |
| **From Source** | macOS 13+, Xcode CLI tools / Xcode, Swift 5.9+ | `.build/` (and optionally user install paths if installer is run) | Modifying CLI/app code, custom local builds, or contributing. |

> **Note:** Installer destination paths can be customized via environment variables:
> `VOCR_APP_INSTALL_DIR="$HOME/Applications" VOCR_BIN_DIR="$HOME/.local/bin" VOCR-1.3.0-macos-arm64/install-vocr-quick-action.sh`
> Because `~/.local/bin` may not be in default `PATH`, invoke the CLI using its absolute path `"$HOME/.local/bin/apple-vision-ocr"`.

## Uninstall

To uninstall, remove the installed paths (adjust them if you set `VOCR_APP_INSTALL_DIR` or `VOCR_BIN_DIR`):

```bash
rm -rf "$HOME/Applications/VOCR.app" \
  "$HOME/.local/bin/apple-vision-ocr" \
  "$HOME/.local/bin/vocr-finder-action" \
  "$HOME/.local/bin/apple-vision-ocr-finder-action" \
  "$HOME/Library/Services/Apple Vision OCR.workflow"
```

## CLI Contract

> **Version note:** the `Progress:` lines and the SIGINT/SIGTERM cleanup below require
> v1.2.0 or later. On v1.1.0, single-process runs print `Completed page N` without a total,
> `--split-workers` runs print no per-page progress, and SIGTERM leaves an
> `apple-vision-ocr-split-*` directory in `$TMPDIR`.

- **Input Rules**:
  - Exactly one input PDF per invocation. Passing a second input file is rejected with exit code `1`.
  - The original input PDF is never modified under any circumstances.
- **Output & Overwrite Rule**:
  - Existing output files are never overwritten.
  - If the target output path exists, the command terminates immediately with exit code `5` and prints `error: output already exists: <path>`.
  - Always provide a fresh destination via `--output <path>` or `--txt-output <path>`.
- **stdout**:
  - Emits only the written output file paths, one per line.
  - Searchable PDF path is printed first, followed by the TXT path (if text output was requested).
- **stderr**:
  - Human-readable status messages and logs.
  - Machine-parseable progress updates after each completed page: `Progress: <completed>/<total> pages` (emitted across all execution modes, including `--split-workers`). Counts only increase; when pages finish together a count can be skipped, but a successful run always ends with `Progress: <total>/<total> pages`.
  - Error messages prefixed with `error: <message>` upon failure.
- **Exit Codes**:
  | Exit Code | Name | Description |
  | :--- | :--- | :--- |
  | `0` | Success | OCR completed successfully. |
  | `1` | Invalid usage | Invalid arguments, multiple input files, or unsupported flags. |
  | `2` | Input file problem | Input file missing or not readable. |
  | `3` | PDF/OCR failure | Input is not a valid PDF (`error: failed to open input PDF`), page rendering or output writing failed, or another unexpected error. |
  | `4` | Vision failure | Apple Vision framework error during text recognition. |
  | `5` | Output already exists | Destination file already exists (overwrite refused). |
  | `130` | Canceled by SIGINT | Interrupted by SIGINT (Ctrl-C). |
  | `143` | Canceled by SIGTERM | Terminated by `kill -TERM <pid>`. Temporary files cleaned up, no partial output left. Repeated signals are ignored while cleanup runs; `kill -KILL` forces an exit but skips cleanup. A signal that arrives after the outputs were written does not change the result: the run exits `0`. |
- **`--dry-run` Limits**:
  - `--dry-run` validates arguments, checks input file existence, checks output path collisions, and prints planned output paths without running OCR.
  - It does not open or parse the PDF (a non-PDF file still passes with exit `0` and fails later with exit `3`), does not perform text recognition, and does not prove Apple Vision works in the current environment (e.g. inside sandboxes).

## Background And Long Jobs

Run long jobs detached. Each job gets a fresh directory holding the CLI's own PID (so you can
signal it directly), its stdout/stderr, and its exit code.

Start a job:

```bash
CLI="$HOME/.local/bin/apple-vision-ocr"
export JOB="$(mktemp -d "${TMPDIR:-/tmp}/ocr-job.XXXXXX")"   # new directory per job; exported for the inner sh
echo "$JOB"                                                  # keep this path to poll or cancel later

nohup sh -c '"$0" "$@" >"$JOB/out" 2>"$JOB/err" & echo $! >"$JOB/pid"; wait $!; echo $? >"$JOB/exit"' \
  "$CLI" "$PWD/in.pdf" --txt-only --txt-output "$PWD/out.txt" --split-workers 8 \
  </dev/null >/dev/null 2>&1 &
```

Poll it (set `JOB` to the printed path first if you are in a new shell):

```bash
grep '^Progress:' "$JOB/err" | tail -n 1                                    # empty until the first page finishes
[ -f "$JOB/exit" ] && { echo "exit=$(cat "$JOB/exit")"; cat "$JOB/out"; }   # finished when the exit file exists
```

Cancel it (only when you want to stop the job):

```bash
kill -TERM "$(cat "$JOB/pid")"   # exit 143; workers, temp files, and partial output are removed
```

Notes:

- Use absolute paths for the input and outputs; the wrapper does not change directory.
- If `err` contains `error:`, read the exit code table above before retrying. Exit `5` means pick a new output path.
- Remove the job directory when you no longer need it: `rm -rf "$JOB"`.

## Recommended Options

Tune throughput and accuracy according to document characteristics:

| Option / Flag | Recommended Setting | Description |
| :--- | :--- | :--- |
| `--recognition-level` | `accurate` (default) | Required for Korean and default `ko,en`. `fast` only supports English. |
| `--split-workers` | `2-16` (~2/3 of CPU cores; ~12 on 18-core Mac) | Multi-process parallelism across pages for large PDFs. In-process `--page-parallelism` does not add throughput due to Vision framework serialization. |
| `--no-language-correction` | Included on clean scans | ~2.5x faster processing with near-identical accuracy on clean scans. |
| `--render-scale` | `1.5` | Faster rasterization for Korean documents while maintaining high recognition quality (default `2.0`). |

## Headless Notes

- The CLI needs no window, prompt, or user interaction. It was verified from `nohup` detached shells (the job keeps running after the launching shell exits, and the output is byte-identical to a foreground run) and from the release package with a minimal `PATH` and no Xcode.
- `VOCR.app` and its `VOCR_HEADLESS` environment variable are an internal GUI test seam that opens a window. AI agents should not use `VOCR.app` or `VOCR_HEADLESS`; agents should always invoke the `apple-vision-ocr` CLI directly.

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

### Prebuilt Package
- macOS 13 or later.
- Apple Silicon (arm64) Mac.
- Xcode is not needed for the prebuilt package.

### Building From Source
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
