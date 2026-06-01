# Apple Vision OCR CLI / VOCR

Swift-only macOS OCR tool using Apple Vision. It includes:

- `apple-vision-ocr`: terminal CLI.
- `VOCR.app`: Finder-launched GUI with detail window and menu bar progress.
- `Apple Vision OCR`: one Finder Quick Action for selected PDF files.

Current release: `v1.0.0`.

## Scope

- Input: one or more PDF files.
- Output: searchable PDF, TXT, or both.
- OCR engine: Apple Vision text recognition.
- Default languages: Korean and English, configurable with `--lang`.
- Original PDFs are never modified.

## Requirements

- macOS 13 or later.
- Xcode command line tools or Xcode with Swift 5.9 or later.

## Documentation

- Human guide: `docs/user-guide.md`
- AI/automation install and setup guide: `docs/ai-install-and-setup.md`
- Implementation status: `CURRENT_STATUS.md`

## Install

Build and run from the checkout:

```bash
swift run apple-vision-ocr input.pdf
```

Install the CLI, `VOCR.app`, and the Finder Quick Action for the current macOS user:

```bash
scripts/install-vocr-quick-action.sh
```

By default the installer writes only user-local files:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

The app and binary locations can be customized per user:

```bash
VOCR_APP_INSTALL_DIR="$HOME/Applications" \
VOCR_BIN_DIR="$HOME/.local/bin" \
scripts/install-vocr-quick-action.sh
```

The Finder workflow is always installed under the current user's `~/Library/Services`.
No original PDF is modified by the CLI or Finder workflow.

## Usage

```bash
swift run apple-vision-ocr input.pdf
swift run apple-vision-ocr input.pdf --output custom.pdf
swift run apple-vision-ocr input.pdf --txt
swift run apple-vision-ocr input.pdf --txt-only
swift run apple-vision-ocr input.pdf --txt-output custom.txt --page-breaks
swift run apple-vision-ocr input.pdf --txt-only --txt-output custom.txt --page-breaks
swift run apple-vision-ocr input.pdf --lang ko,en
swift run apple-vision-ocr input.pdf --recognition-level accurate
swift run apple-vision-ocr input.pdf --recognition-level accurate --page-parallelism 8
swift run apple-vision-ocr input.pdf --recognition-level accurate --page-parallelism 8 --render-scale 1.5
swift run apple-vision-ocr input.pdf --txt-only --page-range 1-100
swift run apple-vision-ocr input.pdf --txt-only --split-workers 4 --page-parallelism 4 --render-scale 2.0
swift run apple-vision-ocr english.pdf --lang en --recognition-level fast --page-parallelism 8
swift run apple-vision-ocr input.pdf --dry-run
swift run apple-vision-ocr --help
swift run apple-vision-ocr --version
```

Default output:

```text
input.pdf -> input_ocr.pdf
```

The CLI refuses to overwrite existing output files.

Optional text output:

```text
--txt                 also writes input.txt
--txt-output PATH     also writes OCR text to PATH
--txt-only            writes only TXT; default path is input.txt
--page-breaks         adds ===== Page N ===== separators to TXT output
```

Speed controls:

```text
--recognition-level accurate|fast   accurate is the default; fast only supports a limited language set
--page-parallelism 1-16             OCR up to N pages from the current PDF at once; default is 8
--render-scale 1.25|1.5|2.0         2.0 quality, 1.5 balanced Korean speed, 1.25 compact
--page-range START-END              text-only OCR over a 1-based page range
--split-workers 2-8                 split text-only OCR across child processes, then join text in order
```

Apple Vision's `fast` recognition level does not support Korean (`ko-KR`) on this macOS version. Korean/default `ko,en` OCR should use `accurate` plus `--page-parallelism` and, when speed matters more than maximum scan fidelity, `--render-scale 1.5`.

For large text-only Korean jobs where quality must stay on `accurate` + `--render-scale 2.0`, prefer `--split-workers 4 --page-parallelism 4`. On the 398-page reference PDF this measured `66.43s` versus the previous `229.48s` baseline, with byte-for-byte identical text output. `--split-workers` and `--page-range` are currently text-only; searchable PDF output still uses the single-process PDF writer path.

## VOCR Finder GUI

Finder shows one Quick Action:

```text
Apple Vision OCR
```

Selecting it opens `VOCR.app`. The detail window has independent output checkboxes:

```text
TXT 추출                    -> input.txt
  Page 구분자 넣기           -> adds ===== Page N ===== headings to TXT
Searchable PDF 생성          -> input_ocr.pdf
```

You can select TXT, Searchable PDF, or both. `Page 구분자 넣기` is only available when `TXT 추출` is selected.

The `동시 OCR 페이지 수` control defaults to 8 and sets how many pages within the current PDF can run at the same time. Selected PDFs are processed one file at a time so the total number of active Apple Vision requests stays within this value.
This value can be changed while OCR is running or paused. Lowering it does not stop pages already inside OCR; it limits how many new pages can start next.

The `인식 모드` control shows `정확도 우선` and `속도 우선 (영문 전용)`. `속도 우선` is blocked for the current Korean-default workflow because Apple Vision's fast text-recognition level does not support Korean.
The `한국어 속도/품질` control keeps Korean OCR on `정확도 우선` and adjusts only the PDF render scale:

```text
품질 우선 (2.0x)
한국어 속도 균형 (1.5x)
빠른 초안 (1.25x)
```

`시작 후 백그라운드로 전환` controls whether pressing `시작` hides the detail window and leaves progress in the menu bar. If unchecked, the detail window stays in front while OCR runs.

The GUI uses safe sibling names if output already exists:

```text
input_ocr.pdf, input_ocr(1).pdf
input.txt, input(1).txt
```

During OCR, the menu bar item shows progress like:

```text
VOCR 38%
```

Left-click opens the detail window. Right-click opens controls:

```text
상세 창 보기
일시정지 / 이어서 진행
취소
종료
```

Pause and cancel are applied at page boundaries. A page already inside Apple Vision recognition is allowed to finish first.
Closing the detail window keeps VOCR running from the menu bar and removes the Dock icon.
The option window also includes `종료` when OCR is not running.
When a job reaches a terminal state (`완료`, `취소`, or `실패`), VOCR exits automatically after a short delay.

If a selected PDF already contains selectable/searchable text and `Searchable PDF 생성` is selected, VOCR shows a warning before starting. If you continue, pages with existing selectable text are rasterized first, then new OCR text is overlaid. This avoids duplicate selectable text while preserving the original PDF file.

Planned future work for image-internal page numbers and partial page selection is documented in:

```text
docs/internal-page-number-and-page-selection-plan.md
```

Future OCR backend experiments and rejected speed candidates are summarized in:

```text
docs/future-ocr-backends.md
docs/benchmarks/2026-05-17-ocr-model-candidates.md
docs/benchmarks/2026-05-29-vision-pipeline-render-ahead.md
```

## Development

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
scripts/package-vocr-app.sh
```

## User Data

Quick Action logs are written under the current user's Library:

```text
~/Library/Logs/vocr-quick-action.log
```

Menu bar/detail progress snapshots are written under the current user's Application Support directory:

```text
~/Library/Application Support/VOCR/progress/latest.json
```

The sample verification files live in `Samples/`:

- `sample.pdf`: image-only OCR fixture.
- `sample_ocr.pdf`: generated searchable output from the CLI.

## Project Notes

- Current implementation status: `CURRENT_STATUS.md`
- Future OCR backend notes: `docs/future-ocr-backends.md`
- Benchmark notes: `docs/benchmarks/`
- Historical design handoff docs: `docs/superpowers/specs/`

## License

MIT. See `LICENSE`.
