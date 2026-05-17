# Apple Vision OCR CLI Implementation Plan

## Scope

Implement v1 as a Swift-only macOS command-line tool that accepts one PDF and writes a new searchable sibling PDF. The tool will use Apple Vision directly, preserve original page appearance by redrawing source PDF pages, and add invisible selectable text overlays.

## Steps

1. Create a Swift Package with an executable product named `apple-vision-ocr`, a small executable entry point, and testable core code.
2. Implement manual CLI parsing for input PDF, `--output`, `--lang`, `--recognition-level`, `--dry-run`, `--help`, and `--version`.
3. Add safe output-path derivation and validation that refuses existing output files and never writes over the input.
4. Render PDF pages to OCR-friendly `CGImage` bitmaps using CoreGraphics.
5. Run `VNRecognizeTextRequest` with default languages `ko,en`, configurable language override, and fast/accurate recognition levels.
6. Keep Vision-to-PDF coordinate conversion isolated in `GeometryMapper`.
7. Write a new PDF by drawing each source page and adding invisible text with CoreText/CoreGraphics.
8. Verify with unit tests, `swift build`, `swift test`, and a sample PDF run that produces selectable text while leaving the original unchanged.

## Constraints

- Keep changes inside this repository.
- Do not add GUI code.
- Do not modify or depend on OwlOCR.
- Do not add Python, Node, uv, or external PDF runtime dependencies.
- Use short-running build/test/manual commands and clean up any temporary processes before final reporting.
