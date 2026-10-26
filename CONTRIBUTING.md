# Contributing

Thanks for helping improve Apple Vision OCR CLI / VOCR.

## Before you start

- Bugs and feature ideas: open an issue first using the templates, so the change can be discussed before you write code.
- Security problems: do not open a public issue. Follow `SECURITY.md`.
- Read `docs/architecture-and-modification-guide.md` before changing the OCR pipeline, split workers, or the VOCR GUI.

## Development setup

Requirements: macOS 26 or later (Apple Silicon), Xcode command line tools (Swift 5.9 or later). Users on macOS 13–25 should continue using [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1).

Run `eval "$(scripts/fetch-layout-model.sh)"` before running tests or commands that need the real layout model (unit tests use mocks and do not require it):

```bash
eval "$(scripts/fetch-layout-model.sh)"
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
scripts/package-vocr-app.sh
```

The `eval` command sets `APPLE_VISION_OCR_LAYOUT_MODEL` in the current shell so `swift run` and `.build/*/apple-vision-ocr` can find the compiled model.

To try the Finder Quick Action from your checkout, run `scripts/install-vocr-quick-action.sh`.

## Pull requests

1. Fork the repository and create a branch from `master`.
2. Keep the change focused on one problem.
3. Add or update tests in `Tests/` when behavior changes.
4. Run `swift test` and confirm it passes.
5. Update `README.md`, `docs/`, and `CHANGELOG.md` when user-visible behavior changes. If you change `README.md` or `docs/user-guide.md`, update the Korean translation (`README.ko.md`, `docs/user-guide.ko.md`) too, or say in the PR that it still needs updating.
6. Open the pull request and fill in the template.

## Ground rules

- Original PDFs must never be modified.
- Korean/default OCR stays on Apple Vision `accurate`; `fast` does not support Korean.
- Performance claims need a measurement (command, machine, before/after time). See `docs/benchmarks/` and `scripts/bench.sh`.

By contributing, you agree that your contributions are licensed under the MIT License (`LICENSE`) and that you follow the `CODE_OF_CONDUCT.md`.
