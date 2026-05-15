# Apple Vision OCR CLI

Handoff state: design approved, implementation not started.

Read this first:

- `docs/superpowers/specs/2026-05-16-apple-vision-ocr-cli-design.md`

Goal for v1:

- Build a Swift-only macOS CLI.
- Input: one PDF file.
- Output: sibling searchable PDF named like `input_ocr.pdf`.
- OCR engine: Apple Vision text recognition.
- Default languages: Korean and English, configurable with `--lang`.
- No GUI and no in-place overwrite in v1.

