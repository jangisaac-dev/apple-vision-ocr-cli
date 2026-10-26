# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Layout-aware Markdown output: CLI flags `--md-only` (writes `<input>.md`) and `--md-output PATH` (writes Markdown to PATH). Exclusive with PDF and TXT options (`--output`, `--txt`, `--txt-only`, `--txt-output`, `--page-breaks`). Structures paper titles as `# `, section headings as `## `, page markers (`[p. 713]` or `[PDF p. 5]`), body paragraphs (preserving OCR line breaks, `#` escaped as `\#`), tables as Markdown tables (via Apple Vision's `RecognizeDocumentsRequest`), and footnotes (`[^4]` references in the body and definitions collected at document end after `<!-- footnotes -->`). Automatically removes running headers, footers, page numbers, and logos (e.g. KCI watermarks), and recovers text from empty regions via re-crop OCR.
- Multi-process split worker support for Markdown (`--split-workers N`), where child worker processes write intermediate `MarkdownPage` JSON structures via internal `--md-pages-output` and the parent process renders the final Markdown document once.
- VOCR GUI output checkbox "Markdown (layout)" / "Markdown (레이아웃 구분)"; selecting it turns off and disables the TXT, page separator, and Searchable PDF options.
- `scripts/fetch-layout-model.sh` script to download pinned PP-DocLayoutV3 CoreML model files, verify SHA-256 checksums, and compile `PPDocLayoutV3.mlmodelc` into `.build/models/`.

### Changed

- Minimum system requirement raised to macOS 26 or later on Apple Silicon. Users on macOS 13–25 should continue using [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1). The installer stops on older macOS versions before making changes.
- CLI installation (`scripts/install-vocr-quick-action.sh`) creates `~/.local/bin/apple-vision-ocr` as a symlink into `VOCR.app` so the CLI can locate the bundled layout model at `../Resources/PPDocLayoutV3.mlmodelc`. Copying only the CLI binary elsewhere loses the model unless overridden via `APPLE_VISION_OCR_LAYOUT_MODEL`.
- Exit code 4 now indicates "Vision failure or layout model unavailable".
- Bundled layout model notice: PP-DocLayoutV3 layout model (CoreML, ~90 MB, Apache-2.0, see `THIRD_PARTY_NOTICES.md`) bundled in `VOCR.app/Contents/Resources/PPDocLayoutV3.mlmodelc`.
- Split OCR worker processes (`SplitProcessOCRRunner.swift`, used by both CLI `--split-workers` and the VOCR GUI) are now launched through `/usr/sbin/taskpolicy -c utility`, applying a utility QoS clamp on every thread of each worker so heavy OCR jobs yield CPU to network daemons (VPN/proxy) and foreground apps instead of starving them.
- The VOCR GUI default worker count now uses `OCRJobParallelism.recommendedWorkerCount()` in `Sources/AppleVisionOCRCore/OCRJobOptions.swift`: two-thirds of active cores minus 2, clamped to 2...16 (10 on an 18-core Mac, 3 on an 8-core Mac; previously two-thirds of active cores, or 12 on 18 cores). `OCRJobParallelism.default` stays 8.

## [1.3.1] - 2026-09-14

### Fixed

- The Korean VOCR GUI no longer shows English for messages that were previously hard-coded or passed through from Core: the job-canceled message, the split-mode "OCR <file>" progress text, the eight Core pipeline progress messages (Starting OCR, Existing selectable text found; rasterizing affected pages, Writing output, Completed OCR, Rendering page N, Paused, OCR page N, Completed page N) which the GUI now maps to localized text when displaying them, the canceled-job error, and the "<file>: N page(s)" line in the existing-text alert. Core and CLI output stay English (the CLI stderr contract is unchanged). Other Core error descriptions (which contain file paths and technical detail) still appear in English.
- The split runner now counts progress only from child stderr lines that start with "Completed page " and never above the total page count. Before, any child stdout or stderr line containing that phrase was counted, so a path containing it could over-count.
- After all split workers exit successfully, the runner waits at most 5 seconds for their output pipes to close instead of waiting forever; previously a worker descendant holding the pipe open could hang the job after every chunk was written.

### Changed

- The release package README.txt now links to the AI agent install and usage guide (docs/ai-install-and-setup.md).

## [1.3.0] - 2026-09-13

### Changed

- GUI is English by default with Korean support that follows the macOS language.
- CI uses actions/checkout@v7.

## [1.2.0] - 2026-09-13

### Added

- CLI prints `Progress: <completed>/<total> pages` on stderr after each page in every mode, including `--split-workers`. Counts only increase and a successful run ends with `<total>/<total>`.
- CLI handles SIGINT/SIGTERM: stops worker processes, removes temporary split files, leaves no partial output, and exits 130/143. Repeated signals are ignored while cleanup runs.
- `--help` documents the stdout/stderr contract and exit codes.
- AI agent install and usage guide (`docs/ai-install-and-setup.md`: install without Xcode, portable use, CLI contract, background jobs) and `AGENTS.md`.
- App icon for `VOCR.app`.
- Korean translations: `README.ko.md`, `docs/user-guide.ko.md`.
- Contributing guide, code of conduct, security policy, and issue/PR templates.

### Fixed

- `--split-workers` runs printed no per-page progress.
- SIGTERM during a `--split-workers` run left an `apple-vision-ocr-split-*` directory in `$TMPDIR`.

## [1.1.0] - 2026-09-13

### Added

- Release package `VOCR-<version>-macos-arm64.zip` with a prebuilt `VOCR.app`, installer, `Install.command`, and SHA-256 file (`scripts/make-release-package.sh`).
- `--split-workers` for searchable PDF output and for combined TXT + PDF output; PDF chunks are merged in page order with the text layer preserved.
- `--split-workers` works with `--page-breaks`.
- VOCR GUI runs multi-process OCR (`동시 워커 프로세스 수`), with pause and cancel.
- `--no-language-correction` flag and GUI checkbox (opt-in; about 2.5x faster, default unchanged).
- CI workflow (`swift build` + `swift test` on macOS) and benchmark scripts (`scripts/bench.sh`, `scripts/make-bench-fixture.py`, `scripts/verify-equivalence.sh`).
- Architecture and modification guide (`docs/architecture-and-modification-guide.md`).

### Changed

- `--split-workers` upper bound raised from 8 to 16.
- VOCR runs as a menu bar agent with no Dock icon.
- The GUI file list scrolls vertically and horizontally instead of growing the window.
- The installer uses a prebuilt app when present, replaces the app via a staged copy, and strips quarantine.

### Fixed

- `--page-range` was ignored under `--split-workers`.
- Page-break markers were lost in the GUI split path.
- The installed `apple-vision-ocr-finder-action` alias.
- Custom `VOCR_APP_INSTALL_DIR` installs launched the wrong app from the Finder workflow.

## [1.0.0] - 2026-06-02

### Added

- `apple-vision-ocr` CLI: searchable PDF and TXT output with Apple Vision, Korean and English by default.
- `VOCR.app` Finder GUI with menu bar progress, and the `Apple Vision OCR` Finder Quick Action.
- `--page-parallelism`, `--render-scale`, `--page-range`, and split-worker text OCR.

[Unreleased]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.0.0
