<p align="center">
  <img src="assets/icon/VOCR-1024.png" alt="VOCR icon" width="128" height="128">
</p>

<h1 align="center">Apple Vision OCR CLI / VOCR</h1>

<p align="center">
  <a href="https://github.com/jangisaac-dev/apple-vision-ocr-cli/actions/workflows/ci.yml"><img src="https://github.com/jangisaac-dev/apple-vision-ocr-cli/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/latest"><img src="https://img.shields.io/github/v/release/jangisaac-dev/apple-vision-ocr-cli" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/jangisaac-dev/apple-vision-ocr-cli" alt="License: MIT"></a>
</p>

<p align="center">English | <a href="README.ko.md">한국어</a></p>

Swift-only macOS OCR tool using Apple Vision. It includes:

- `apple-vision-ocr`: terminal CLI.
- `VOCR.app`: Finder-launched GUI with detail window and menu bar progress.
- `Apple Vision OCR`: one Finder Quick Action for selected PDF files.

Current release: `v1.2.0`.

## Scope

- Input: PDF files. The CLI takes one PDF per run; VOCR and the Quick Action accept several selected PDFs.
- Output: searchable PDF, TXT, or both.
- OCR engine: Apple Vision text recognition.
- Default languages: Korean and English, configurable with `--lang`.
- Original PDFs are never modified.

## Requirements

- macOS 13 or later.
- Release package: an Apple Silicon (arm64) Mac. No build tools needed.
- Building from source: Xcode command line tools or Xcode with Swift 5.9 or later.

## Documentation

- Human guide: `docs/user-guide.md`
- AI agent install and usage guide (install without Xcode, CLI contract, exit codes, background jobs): `docs/ai-install-and-setup.md`, plus `AGENTS.md` for coding agents
- Architecture and modification guide: `docs/architecture-and-modification-guide.md`
- Implementation status: `CURRENT_STATUS.md`
- Changelog: `CHANGELOG.md`
- Contributing: `CONTRIBUTING.md`
- Korean (한국어): `README.ko.md`, `docs/user-guide.ko.md`

## Install

### From a release package (no build)

1. Download `VOCR-<version>-macos-arm64.zip` from [GitHub Releases](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases) and unzip it.
2. Double-click `Install.command`. If macOS blocks it, open System Settings > Privacy & Security, click "Open Anyway", and run it again (or use the Terminal commands below).
3. In Finder, select PDFs, right-click, and choose Quick Actions > `Apple Vision OCR`.

The package contains the prebuilt `VOCR.app` (with the bundled `apple-vision-ocr` CLI) and the same installer as the checkout; it installs to the paths listed below. The app is ad-hoc signed and not notarized, so the installer removes the quarantine attribute from the installed copy. Terminal alternative:

```bash
xattr -dr com.apple.quarantine VOCR-<version>-macos-arm64
VOCR-<version>-macos-arm64/install-vocr-quick-action.sh
```

Maintainers build the package with `scripts/make-release-package.sh` (output: `.release/`).

### From source

Build and run from the checkout:

```bash
swift run apple-vision-ocr input.pdf
```

Install the CLI, `VOCR.app`, and the Finder Quick Action for the current macOS user:

```bash
scripts/install-vocr-quick-action.sh
```

By default the installer writes only user-local files:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

The app and binary locations can be customized per user:

```bash
VOCR_APP_INSTALL_DIR="$HOME/Applications" \
VOCR_BIN_DIR="$HOME/.local/bin" \
scripts/install-vocr-quick-action.sh
```

The Finder workflow is always installed under the current user's `~/Library/Services`.
No original PDF is modified by the CLI or Finder workflow.

## Usage

```bash
swift run apple-vision-ocr input.pdf
swift run apple-vision-ocr input.pdf --output custom.pdf
swift run apple-vision-ocr input.pdf --txt
swift run apple-vision-ocr input.pdf --txt-only
swift run apple-vision-ocr input.pdf --txt-output custom.txt --page-breaks
swift run apple-vision-ocr input.pdf --txt-only --txt-output custom.txt --page-breaks
swift run apple-vision-ocr input.pdf --lang ko,en
swift run apple-vision-ocr input.pdf --recognition-level accurate
swift run apple-vision-ocr input.pdf --recognition-level accurate --page-parallelism 8
swift run apple-vision-ocr input.pdf --recognition-level accurate --page-parallelism 8 --render-scale 1.5
swift run apple-vision-ocr input.pdf --txt-only --page-range 1-100
swift run apple-vision-ocr input.pdf --txt-only --split-workers 4 --render-scale 2.0
swift run apple-vision-ocr english.pdf --lang en --recognition-level fast --page-parallelism 8
swift run apple-vision-ocr input.pdf --dry-run
swift run apple-vision-ocr --help
swift run apple-vision-ocr --version
```

Default output:

```text
input.pdf -> input_ocr.pdf
```

The CLI refuses to overwrite existing output files.

Optional text output:

```text
--txt                 also writes input.txt
--txt-output PATH     also writes OCR text to PATH
--txt-only            writes only TXT; default path is input.txt
--page-breaks         adds ===== Page N ===== separators to TXT output
```

Speed controls:

```text
--recognition-level accurate|fast   accurate is the default; fast only supports a limited language set
--page-parallelism 1-16             OCR up to N pages from the current PDF at once; default is 8
--render-scale 1.25|1.5|2.0         2.0 quality, 1.5 balanced Korean speed, 1.25 compact
--page-range START-END              OCR over a 1-based page range (TXT, PDF, or both)
--split-workers 2-16                split OCR across child processes (TXT, searchable PDF, or both), then join output in order
```

Apple Vision's `fast` recognition level does not support Korean (`ko-KR`) on this macOS version. Korean/default `ko,en` OCR should use `accurate` plus `--page-parallelism` and, when speed matters more than maximum scan fidelity, `--render-scale 1.5`.

For large jobs where quality must stay on `accurate` + `--render-scale 2.0`, raise `--split-workers` toward the core-count sweet spot (~12 on an 18-core machine). An early `--split-workers 4` run on the 398-page reference PDF measured `66.43s` versus the `229.48s` single-process baseline, with byte-for-byte identical text output; more workers scale further. The `--page-parallelism` value you pass is not forwarded to split workers: each worker runs with its own default (8), which still helps because it overlaps rendering with recognition inside that worker. Set `APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM` to override it for benchmarking.

In-process `--page-parallelism` does not raise throughput: Apple Vision serializes recognition within a single process, so it pins only ~1-2 cores regardless of the value. `--split-workers` is the real parallelism knob — it runs N independent processes and saturates the machine. It now applies to both text-only and searchable PDF output (PDF chunks are merged in page order with the searchable text layer preserved). On an 18-core machine, ~12 workers is the practical sweet spot.

## VOCR Finder GUI

Finder shows one Quick Action:

```text
Apple Vision OCR
```

Selecting it opens `VOCR.app`. The detail window has independent output checkboxes:

```text
TXT 추출                    -> input.txt
  Page 구분자 넣기           -> adds ===== Page N ===== headings to TXT
Searchable PDF 생성          -> input_ocr.pdf
```

You can select TXT, Searchable PDF, or both. `Page 구분자 넣기` is only available when `TXT 추출` is selected.

The `동시 워커 프로세스 수` control defaults to an auto value based on CPU cores (about two-thirds of the active processors, capped at 16) and sets how many child OCR processes run in parallel. When it is 2 or more, VOCR splits the document across that many `apple-vision-ocr` worker processes for TXT, Searchable PDF, or both — Apple Vision serializes recognition within one process, so multi-process is what actually uses every core (about 6x faster on long PDFs). When set to 1, VOCR runs the in-process single-process path instead. The bundled CLI is found inside `VOCR.app` (or via `VOCR_CLI_PATH`); if it cannot be found, VOCR falls back to single-process and notes it in the log.

The `인식 모드` control shows `정확도 우선` and `속도 우선 (영문 전용)`. `속도 우선` is blocked for the current Korean-default workflow because Apple Vision's fast text-recognition level does not support Korean.
The `한국어 속도/품질` control keeps Korean OCR on `정확도 우선` and adjusts only the PDF render scale:

```text
품질 우선 (2.0x)
한국어 속도 균형 (1.5x)
빠른 초안 (1.25x)
```

`시작 후 백그라운드로 전환` controls whether pressing `시작` hides the detail window and leaves progress in the menu bar. If unchecked, the detail window stays in front while OCR runs.

The GUI uses safe sibling names if output already exists:

```text
input_ocr.pdf, input_ocr(1).pdf
input.txt, input(1).txt
```

During OCR, the menu bar item shows progress like:

```text
VOCR 38%
```

Left-click opens the detail window. Right-click opens controls:

```text
상세 창 보기
일시정지 / 이어서 진행
취소
종료
```

Pause and cancel are applied at page boundaries. A page already inside Apple Vision recognition is allowed to finish first.
VOCR runs as a menu bar agent (`LSUIElement`), so it never shows a Dock icon — at launch the window appears without a Dock tile, and OCR runs in the background from the menu bar. Closing the detail window keeps VOCR running from the menu bar.
The option window also includes `종료` when OCR is not running.
When a job reaches a terminal state (`완료`, `취소`, or `실패`), VOCR exits automatically after a short delay.

If a selected PDF already contains selectable/searchable text and `Searchable PDF 생성` is selected, VOCR shows a warning before starting. If you continue, pages with existing selectable text are rasterized first, then new OCR text is overlaid. This avoids duplicate selectable text while preserving the original PDF file.

Planned future work for image-internal page numbers and partial page selection is documented in:

```text
docs/internal-page-number-and-page-selection-plan.md
```

Future OCR backend experiments and rejected speed candidates are summarized in:

```text
docs/future-ocr-backends.md
docs/benchmarks/2026-05-17-ocr-model-candidates.md
docs/benchmarks/2026-05-29-vision-pipeline-render-ahead.md
```

## Development

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
scripts/package-vocr-app.sh
```

## User Data

Quick Action logs are written under the current user's Library:

```text
~/Library/Logs/vocr-quick-action.log
```

Menu bar/detail progress snapshots are written under the current user's Application Support directory:

```text
~/Library/Application Support/VOCR/progress/latest.json
```

The sample verification files live in `Samples/`:

- `sample.pdf`: image-only OCR fixture.
- `sample_ocr.pdf`: generated searchable output from the CLI.

## Project Notes

- Current implementation status: `CURRENT_STATUS.md`
- Future OCR backend notes: `docs/future-ocr-backends.md`
- Benchmark notes: `docs/benchmarks/`
- Historical design handoff docs: `docs/superpowers/specs/`

## License

MIT. See `LICENSE`.
