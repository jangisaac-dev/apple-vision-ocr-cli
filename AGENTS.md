# AGENTS.md

## Repository Overview
Apple Vision OCR CLI (`apple-vision-ocr`) and companion menu bar app (`VOCR.app`) for macOS (Apple Silicon). It provides fast, accurate OCR for PDFs producing searchable PDFs, plain text, or both using the Apple Vision framework.

## Installation and CLI Usage
See [docs/ai-install-and-setup.md](docs/ai-install-and-setup.md) for complete agent instructions, copy-paste install commands, background execution patterns, exit codes, and speed tuning.

## Development Commands
```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
scripts/package-vocr-app.sh
```

## Agent Rules
- **Never modify input PDFs**: Always output to new target files (`input_ocr.pdf`, `input.txt`, or explicit `--output`/`--txt-output`).
- **Korean OCR stays accurate**: Korean/default `ko,en` must use `--recognition-level accurate` (`fast` does not support Korean). Use `--split-workers`, `--no-language-correction`, or `--render-scale 1.5` to accelerate jobs.
- **Sync localized documentation**: Any changes to `README.md` or `docs/user-guide.md` must be mirrored in `README.ko.md` and `docs/user-guide.ko.md`.
- **Benchmark performance claims**: Any performance claims or optimizations require empirical benchmark measurements.
- **Keep repository clean**: Never commit `.build/`, `.workflow_build/`, `.release/`, `.ai-runs/`, or log files.

## Architecture and References
- Architecture guide: [docs/architecture-and-modification-guide.md](docs/architecture-and-modification-guide.md)
- Human user guide: [docs/user-guide.md](docs/user-guide.md)
- Status and history: [CURRENT_STATUS.md](CURRENT_STATUS.md), [CHANGELOG.md](CHANGELOG.md)
