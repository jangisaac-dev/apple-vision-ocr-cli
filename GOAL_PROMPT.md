# Goal Prompt

Paste this into a fresh Codex session opened at:

```bash
cd /Volumes/ssd/simple_tools/apple-vision-ocr-cli
```

Prompt:

```text
Goal: Implement v1 of the Apple Vision OCR CLI in this repository.

You are starting in /Volumes/ssd/simple_tools/apple-vision-ocr-cli. First read README.md and docs/superpowers/specs/2026-05-16-apple-vision-ocr-cli-design.md. Treat that design as the approved source of truth.

Build a Swift-only macOS CLI that accepts one PDF and creates a sibling searchable PDF named like input_ocr.pdf. The output must preserve the visual appearance of the original PDF and add copyable/searchable OCR text using Apple Vision. Default OCR languages are ko,en, with a --lang override. Do not add a GUI. Do not modify /Applications/OwlOCR.app. Do not depend on OwlOCR internals. Do not add Python, Node, uv, or external PDF runtime dependencies for v1.

Before implementation, create a concise implementation plan from the design. Then implement inside this repository only.

Minimum implementation expectations:
- Swift Package executable.
- CLI options for input PDF, --output, --lang, --recognition-level, --dry-run, --help, and --version.
- Safe default output path: input.pdf -> input_ocr.pdf.
- Refuse accidental overwrites in v1.
- PDF page rendering for Vision OCR.
- Apple Vision text recognition with default languages ko,en.
- Geometry mapping from Vision normalized bounding boxes to PDF page coordinates.
- New PDF writer that draws original pages and overlays invisible/copyable text.
- Unit tests for output path derivation, language parsing, CLI validation, and geometry mapping.
- Verification that the generated PDF opens, visually matches the input, and has selectable/copyable text.

Operational constraints:
- Keep all changes inside this repository.
- Use short command timeouts.
- Do not leave Swift, Python, Node, uv, skycomputeruse, or helper processes running.
- If temporary processes are started, inspect and clean them up before final reporting.

Completion criteria:
- swift test passes.
- swift build passes.
- A sample PDF run produces sample_ocr.pdf.
- Original PDF remains unchanged.
- Output PDF text is selectable/copyable.
- Git working tree status is reported at the end.
```

