# Goal Prompt

Paste this into a fresh Codex session opened at the repository root.

```text
Goal: Continue the Apple Vision OCR CLI / VOCR project from the current completed Apple Vision baseline.

Start by reading README.md, CURRENT_STATUS.md, and docs/future-ocr-backends.md. Treat Apple Vision accurate mode as the quality-safe default for Korean/default OCR unless a new benchmark proves otherwise.

Current product shape:
- Swift-only macOS package.
- apple-vision-ocr CLI.
- VOCR Finder-launched app with menu bar progress.
- Finder Quick Action named Apple Vision OCR.
- Default OCR languages are ko,en.
- Korean/default OCR must not use Apple Vision fast mode because fast mode does not support ko-KR on the tested macOS version.
- Normal output should remain searchable PDF and/or TXT without modifying the original PDF.

Important implementation constraints:
- Keep work inside this repository.
- Avoid adding Python, Node, uv, or external OCR runtimes to the product path unless the task is explicitly an experimental benchmark.
- Use short command timeouts.
- Do not leave Swift, Python, Node, uv, skycomputeruse, Ollama, MLX, Tesseract, or helper processes running.
- Before final reporting, inspect and clean up task-created processes.

Current speed/quality decision:
- Apple Vision accurate with page parallelism 8 remains the default.
- Render scale 2.0 is the quality default.
- Render scale 1.5 and 1.25 are operator knobs, not a replacement for accurate mode.
- Tesseract is only a possible rough-draft backend with a visible quality warning.
- RapidOCR, PaddleOCR, and local GLM-OCR MLX should not be default dependencies based on current benchmarks.

Before changing OCR backend behavior:
- Read docs/benchmarks/2026-05-17-ocr-model-candidates.md.
- Run a same-document benchmark against the Apple Vision reference.
- Preserve quality as an acceptance criterion; speed-only output is not enough.

Completion criteria for future work:
- swift test passes.
- swift build or swift build -c release passes.
- Documentation is updated if behavior or benchmark decisions change.
- Git working tree status and process cleanup status are reported at the end.
```
