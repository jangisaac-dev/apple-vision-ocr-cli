# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.0.0
