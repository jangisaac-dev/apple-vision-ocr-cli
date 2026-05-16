# VOCR Finder GUI And Menubar Progress Design

Date: 2026-05-17
Status: Design for review
Project path: `/Volumes/ssd/simple_tools/apple-vision-ocr-cli`

## Objective

Replace the current single-purpose Apple Vision OCR Finder Quick Action with one Finder entry that opens a small macOS GUI and runs OCR with reliable in-app and menu bar progress.

The Finder right-click menu should show one item:

```text
Apple Vision OCR
```

After selecting it, the user chooses the desired output mode in the app instead of choosing among several separate Finder service entries.

## User-Facing Modes

The GUI exposes the same four workflows the user had in the earlier OwlOCR setup, but through options rather than four separate services.

| Mode | GUI Selection | Output |
| --- | --- | --- |
| Text only | `TXT 추출` checked, `검색 가능한 PDF 생성` unchecked, `페이지 구분 포함` unchecked | `input.txt` |
| Searchable PDF only | `검색 가능한 PDF 생성` checked, `TXT 추출` unchecked | `input_ocr.pdf` |
| Text plus searchable PDF | `TXT 추출` checked, `검색 가능한 PDF 생성` checked, `페이지 구분 포함` unchecked | `input.txt` and `input_ocr.pdf` |
| Page-divided text | `TXT 추출` checked, `페이지 구분 포함` checked | `input.txt` with page headings |

The page-divided text format must match the existing OwlOCR Quick Action Python workflow:

```text
===== Page 1 =====

<page text>
```

Text-only extraction and text-plus-PDF extraction do not include page headings unless `페이지 구분 포함` is explicitly enabled.

## Finder Integration

Install one Automator Quick Action at:

```text
~/Library/Services/Apple Vision OCR.workflow
```

The workflow should only forward selected PDF file paths to the GUI app. It should not do OCR work itself and should not attempt to own progress reporting.

Command shape:

```bash
open -a VOCR --args "$@"
```

If passing arguments through `open -a` is unreliable for Finder services, use a thin wrapper script under `~/.local/bin` that launches the app with the selected file paths.

## App Structure

Use a small native macOS app named `VOCR.app`, built from the same Swift package.

Package shape:

```text
AppleVisionOCRCore
  PDF open/render
  Vision OCR
  searchable PDF writing
  TXT writing
  page-count preflight
  progress callback

apple-vision-ocr
  terminal CLI

VOCR.app
  Finder-launched GUI
  menu bar status item
  option selection
  pause/resume/cancel controls
  completion/failure notifications
```

The CLI and GUI should share the same OCR core instead of shelling through the CLI for normal GUI work. This keeps progress, cancellation, and output behavior consistent.

## GUI Window

The GUI opens after the Finder Quick Action receives one or more PDFs.

It shows:

- selected PDF count and filenames;
- `TXT 추출` checkbox;
- `페이지 구분 포함` checkbox nested under text output;
- `검색 가능한 PDF 생성` checkbox;
- start button;
- cancel button;
- progress text for detailed status.

Default selection:

- `검색 가능한 PDF 생성`: on;
- `TXT 추출`: off;
- `페이지 구분 포함`: off.

Validation:

- At least one of `TXT 추출` or `검색 가능한 PDF 생성` must be selected.
- `페이지 구분 포함` is disabled until `TXT 추출` is selected.

## Menu Bar Progress

When work starts, `VOCR.app` creates an `NSStatusItem`.

During processing, the menu bar title should show progress:

```text
VOCR 38%
```

If macOS truncates the item or width is constrained, a compact fallback is acceptable:

```text
38%
```

The menu bar item is the primary progress surface. The window remains useful for options and detailed status, but progress should remain visible even when the window is hidden.

Progress is based on total pages across all selected PDFs:

```text
completed pages / total pages
```

The OCR core reports page completion after each page is recognized and added to the output result. Writing PDF/TXT output can be represented as a final short stage after page OCR reaches 100%.

## Menu Bar Menu

Right-clicking the menu bar item opens a status menu. A normal click can open the same menu as a convenience, but right-click support is required.

During running state:

```text
Apple Vision OCR
<current file name>
<completed> / <total> pages
<percent>%

상세 창 보기
일시정지
취소
```

During paused state:

```text
Apple Vision OCR
일시정지됨
<completed> / <total> pages
<percent>%

상세 창 보기
이어서 진행
취소
```

Only one of `일시정지` or `이어서 진행` should be shown at a time.

Optional useful menu items:

- `상세 창 보기`: brings the GUI window to front.
- `출력 폴더 열기`: shown after success or failure if at least one output folder is known.
- `로그 보기`: shown after failure.

Completion behavior:

- On success, show `VOCR 완료` briefly in the menu bar, send a macOS notification, then remove the status item and quit the app after a short delay unless the window is still open.
- On failure, show `VOCR 실패` and keep the status item long enough for the user to open details or logs.

## Pause, Resume, Cancel

Pause:

- User selects `일시정지`.
- The current page is allowed to finish.
- The job stops before starting the next page.
- Menu changes to `이어서 진행`.

Resume:

- User selects `이어서 진행`.
- Processing continues from the next unprocessed page.

Cancel:

- User selects `취소`.
- The current page is allowed to finish if already inside a Vision request.
- The app stops before any new page starts.
- Partial output files should not be moved into final destination.
- Temporary files are cleaned up.

This page-boundary control is safer than trying to forcibly interrupt `VNRecognizeTextRequest` mid-call.

## Output Policy

Default output paths:

```text
input.pdf -> input_ocr.pdf
input.pdf -> input.txt
```

The existing CLI refuses to overwrite outputs. The GUI should avoid user-facing failures by generating an available sibling path when an output already exists:

```text
input_ocr.pdf
input_ocr(1).pdf
input_ocr(2).pdf

input.txt
input(1).txt
input(2).txt
```

The original input PDF must never be modified.

## Progress Persistence

The app must keep an internal job state model. It should also write a JSON progress file under a user-local app support directory for debugging and future automation:

```text
~/Library/Application Support/VOCR/progress/<job-id>.json
```

The JSON file is not the primary UI transport. The primary progress transport is direct in-process state from the OCR core to the GUI/menu bar.

## Testing Plan

Unit tests:

- output mode mapping;
- default and unique output path generation;
- page-divided text rendering exactly as `===== Page N =====`;
- progress state transitions: running, paused, resumed, canceled, failed, completed;
- cancellation stops before starting the next page.

Integration/manual verification:

- Finder Quick Action opens only one `Apple Vision OCR` item.
- GUI receives selected PDF paths.
- PDF-only mode creates searchable PDF.
- TXT-only mode creates text without page headings.
- TXT plus PDF mode creates both outputs without page headings.
- Page-divided TXT mode uses `===== Page N =====`.
- Menu bar shows live percentage.
- Menu bar menu supports `일시정지`, `이어서 진행`, and `취소`.
- No Automator/OCR/helper processes remain after success, failure, or cancel.

## Non-Goals

- Do not create four separate VOCR Finder menu entries.
- Do not rely on Automator's background gear progress.
- Do not add Python, Node, or uv runtime dependencies to the new Apple Vision path.
- Do not modify OwlOCR workflows.
