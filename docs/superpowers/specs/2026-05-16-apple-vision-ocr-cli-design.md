# Apple Vision OCR CLI Design

Date: 2026-05-16
Status: Implemented baseline. Kept as the original v1 product contract.
Project path: `<repo>`

## Objective

Create a macOS command-line tool that converts an image-only or poorly searchable PDF into a searchable PDF using Apple Vision OCR.

The v1 behavior is intentionally narrow:

- Accept one input PDF.
- Preserve the original visual page appearance.
- Create a new sibling PDF with copyable and searchable OCR text overlaid on each page.
- Never modify the original PDF.
- Default output name: `input_ocr.pdf`.
- Use Apple Vision text recognition directly from Swift.
- Provide a language override while defaulting to Korean and English.

## Non-Goals

V1 does not include:

- GUI.
- Folder batch mode.
- Clipboard OCR.
- Screenshot or screen-region OCR.
- Text-only export.
- In-place overwrite.
- Network OCR or LLM OCR.
- Python, Node, or external PDF command dependencies.

## CLI Contract

Primary command:

```bash
apple-vision-ocr input.pdf
```

Default output:

```text
input.pdf -> input_ocr.pdf
```

Optional arguments:

```bash
apple-vision-ocr input.pdf --output custom.pdf
apple-vision-ocr input.pdf --lang ko,en
apple-vision-ocr input.pdf --recognition-level accurate
apple-vision-ocr input.pdf --dry-run
apple-vision-ocr --version
apple-vision-ocr --help
```

V1 defaults:

- `--lang ko,en`
- `--recognition-level accurate`
- Output path derived from the input path by replacing `.pdf` with `_ocr.pdf`.

Exit codes:

- `0`: success.
- `1`: invalid CLI usage.
- `2`: input file problem.
- `3`: PDF rendering or writing failure.
- `4`: Vision OCR failure.
- `5`: output already exists and cannot be safely written.

The CLI should print human-readable progress to stderr and reserve stdout for machine-friendly output when requested later. V1 can keep stdout minimal.

## Architecture

Use a Swift Package with a single executable target.

Recommended initial package shape:

```text
apple-vision-ocr-cli/
  Package.swift
  README.md
  docs/
    superpowers/
      specs/
        2026-05-16-apple-vision-ocr-cli-design.md
  Sources/
    AppleVisionOCRCLI/
      main.swift
      CLIOptions.swift
      SearchablePDFPipeline.swift
      PDFRenderer.swift
      VisionTextRecognizer.swift
      PDFTextOverlayWriter.swift
      GeometryMapper.swift
      Errors.swift
  Tests/
    AppleVisionOCRCLITests/
      CLIOptionsTests.swift
      GeometryMapperTests.swift
      OutputPathTests.swift
```

Keep the implementation as small components with clear boundaries:

- `CLIOptions`: parse arguments and validate input.
- `SearchablePDFPipeline`: orchestrate page rendering, OCR, and PDF writing.
- `PDFRenderer`: render PDF pages to images suitable for Vision.
- `VisionTextRecognizer`: call `VNRecognizeTextRequest`.
- `GeometryMapper`: convert Vision normalized coordinates into PDF page coordinates.
- `PDFTextOverlayWriter`: write the new PDF by drawing the original page and overlaying invisible text.
- `Errors`: stable error types and exit-code mapping.

## Processing Flow

1. Parse CLI options.
2. Validate that the input exists, is a PDF, and is readable.
3. Resolve the output path:
   - default: sibling `input_ocr.pdf`;
   - explicit: `--output custom.pdf`.
4. Refuse to overwrite an existing output path in v1 unless a future explicit overwrite flag is added.
5. Open the source PDF.
6. For each page:
   - obtain page bounds and rotation;
   - render the page to a bitmap image at an OCR-friendly scale;
   - run Apple Vision text recognition;
   - collect recognized text candidates and bounding boxes;
   - map Vision bounding boxes to PDF coordinates.
7. Create a new PDF.
8. For each output page:
   - draw the original PDF page into the new page;
   - write copyable text at mapped coordinates with invisible rendering.
9. Close and flush the output PDF.
10. Return success with the output path.

## Apple Vision Configuration

Use `VNRecognizeTextRequest`.

Default settings:

- `recognitionLevel = .accurate`
- `recognitionLanguages = ["ko", "en"]`
- `usesLanguageCorrection = true`

Expose `--lang ko,en` as a comma-separated list. The parser should trim whitespace and reject an empty language list.

Expose `--recognition-level fast|accurate`. Default remains `accurate`.
Implementation note added 2026-05-17: Apple Vision's `fast` level does not support `ko-KR` on the tested macOS version, so Korean/default `ko,en` runs must stay on `accurate`; `fast` is valid only for supported language sets such as English.
Implementation note added 2026-05-17: Korean-safe speed work should use `accurate` plus page parallelism and configurable render scale, not Vision `fast`.
Implementation note added 2026-05-17: Default page parallelism is 4 and the page scheduler uses a bounded worker pool to keep OCR slots filled more consistently on machines with available compute.

## PDF Text Overlay Strategy

The output PDF must remain visually equivalent to the input PDF while adding selectable text.

Preferred approach:

- Use CoreGraphics PDF writing APIs.
- Start a new page with the same media box as the original page.
- Draw the original PDF page into the output page.
- Add text overlay using CoreText/CoreGraphics.
- Use invisible text rendering mode if available through the selected drawing API.

If direct invisible text drawing is awkward in Swift APIs, the fallback is to draw text with a fully transparent fill color while preserving extractable text. The implementation must verify that macOS Preview can select/copy the text. If transparent text is not extractable, return to PDF text-rendering mode support rather than shipping a visual-only overlay.

Important: The output must be tested in Preview or `pdftotext` only as verification, not as a runtime dependency.

## Geometry

Vision returns normalized bounding boxes with origin at the lower-left of the image coordinate space. PDF page drawing may involve media box offsets, crop boxes, rotation, and coordinate flips depending on API.

V1 should explicitly handle:

- media box size;
- page rotation values of 0, 90, 180, and 270 degrees;
- image render scale;
- conversion from normalized Vision rectangles to PDF page rectangles.

Start with unit tests for coordinate conversion before wiring full OCR output.

Implementation note:

- Keep all geometry transforms in `GeometryMapper`.
- Do not scatter coordinate conversion across the renderer and writer.
- Add small fixture tests for common page sizes such as US Letter and A4.

## Quality and Limits

V1 should optimize for correctness and handoff clarity, not maximum throughput.

Expected limitations:

- OCR quality depends on Apple Vision and input scan quality.
- Complex layouts may produce text order that is imperfect.
- Exact font matching is not required.
- Text selection should work even if copied line ordering is not perfect.
- Very large PDFs may be slower because pages are processed sequentially.

Possible later improvements:

- Batch folder mode.
- JSON progress output.
- Text-only export.
- OCR cache.
- Parallel page OCR with bounded concurrency.
- Overwrite option.
- Better layout grouping and reading-order reconstruction.

## Testing Plan

Unit tests:

- Output path derivation:
  - `input.pdf -> input_ocr.pdf`
  - `/path/file.name.pdf -> /path/file.name_ocr.pdf`
  - reject non-PDF input.
- Language parsing:
  - `ko,en`
  - `ko, en`
  - reject empty language list.
- Geometry conversion:
  - normalized Vision rect to PDF rect;
  - page rotations;
  - known page sizes.
- CLI validation:
  - missing input;
  - unsupported argument;
  - existing output path behavior.

Integration/manual verification:

- Run the CLI on a small scanned PDF fixture.
- Open output in macOS Preview.
- Confirm text can be selected and copied.
- Confirm the visual page still matches the source page.
- Confirm the original PDF remains unchanged.

Use short command timeouts during testing. Do not leave long-running Swift, Python, Node, uv, or helper processes behind.

## Operational Rules

Follow these project rules during implementation:

- Keep all work inside `<repo>`.
- Do not modify `/Applications/OwlOCR.app`.
- Do not depend on OwlOCR internals.
- Prefer a pure Swift Package.
- Avoid Python, Node, uv, or long-running helper services for the v1 tool.
- If any temporary process is started, check and stop it before ending work.
- Use short timeouts for build/test commands.
- Do not create hidden background services.

## Handoff Checklist For The Next Terminal

Start in:

```bash
cd <repo>
```

Read:

```bash
sed -n '1,240p' docs/superpowers/specs/2026-05-16-apple-vision-ocr-cli-design.md
sed -n '1,220p' GOAL_PROMPT.md
```

Then paste the prompt from `GOAL_PROMPT.md` into the new Codex session and create an implementation plan from this design before writing code.

Suggested first implementation steps:

1. Initialize a Swift Package executable.
2. Add argument parsing and output-path derivation tests.
3. Add `GeometryMapper` and unit tests before PDF writing.
4. Implement single-page PDF render plus Vision OCR.
5. Implement output PDF writer with original page rendering.
6. Add invisible/copyable text overlay.
7. Verify copied text in Preview or via a verification tool.
8. Add README usage examples only after the command works.

Completion criteria for v1:

- `swift test` passes.
- `swift build` passes.
- `apple-vision-ocr sample.pdf` creates `sample_ocr.pdf`.
- The output PDF opens in Preview.
- The output PDF visually matches the input.
- The output PDF text can be selected and copied.
- The original PDF is unchanged.
