# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- CLI prints `Progress: <completed>/<total> pages` on stderr after each page in every mode, including `--split-workers`.
- CLI handles SIGINT/SIGTERM: stops worker processes, removes temporary split files, leaves no partial output, and exits 130/143.
- `--help` documents the stdout/stderr contract and exit codes.
- AI agent install and usage guide (`docs/ai-install-and-setup.md`: install without Xcode, portable use, CLI contract, background jobs) and `AGENTS.md`.
- App icon for `VOCR.app`.
- Korean translations: `README.ko.md`, `docs/user-guide.ko.md`.
- Contributing guide, code of conduct, security policy, changelog, and issue/PR templates.

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

[Unreleased]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.0.0
