# Apple Vision OCR User Guide

English | [한국어](user-guide.ko.md)

Apple Vision OCR turns image-only PDF pages into searchable PDFs, plain text
files, or both. It uses Apple's built-in Vision framework, so it runs locally on
macOS and does not upload your documents.

## What You Need

- macOS 26 or later (Apple Silicon).
- Users on macOS 13–25 should continue using [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1).
- A PDF file. Image-only scans are the main use case.
- For the release package: an Apple Silicon Mac. Nothing else.
- For building from source: Xcode command line tools or Xcode with Swift 5.9 or later.

To use the Finder Quick Action without building anything, download
`VOCR-<version>-macos-arm64.zip` from the
[GitHub Releases](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases)
page, unzip it, and double-click `Install.command`. If macOS blocks it, open
System Settings > Privacy & Security and click "Open Anyway". The package's
`README.txt` has a Terminal alternative and uninstall steps.

To build from source, install the Xcode command line tools if `swift` is not available:

```bash
xcode-select --install
```

## Quick Start

Clone the project and run OCR from the checkout:

```bash
git clone https://github.com/jangisaac-dev/apple-vision-ocr-cli.git
cd apple-vision-ocr-cli
swift run apple-vision-ocr path/to/input.pdf
```

The default output is written next to the input:

```text
input.pdf -> input_ocr.pdf
```

The original PDF is never modified. Existing output files are not overwritten.

## Text Output

Write only a text file:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt-only
```

Write both searchable PDF and text:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt
```

Add page separators to text output:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt-only --page-breaks
```

Choose an explicit text output path:

```bash
swift run apple-vision-ocr path/to/input.pdf \
  --txt-only \
  --txt-output output.txt
```

## Markdown Output

Layout-aware Markdown output formats OCR text into structured Markdown, separating document titles, section headings, body paragraphs, tables, and footnotes without mixing them together.

### What It Contains

- **Title**: Document/paper title formatted as `# Title`.
- **Headings**: Section headings formatted as `## Heading`. All section levels are rendered as `##`.
- **Page Markers**: One marker line per page: `[p. 713]` with the printed page number when recognized, otherwise `[PDF p. 5]`.
- **Paragraphs**: Body paragraphs with OCR-preserved line breaks. Any line starting with `#` is escaped as `\#`.
- **Tables**: Page tables recognized using Apple Vision document analysis (`RecognizeDocumentsRequest`) and converted to Markdown tables.
- **Footnotes**: Footnote references like `[^4]` linked inline in body text (or placed on the page marker line `[p. 713] [^4]` if the reference mark cannot be found in the body). All footnote definitions are collected at the end of the document after a `<!-- footnotes -->` separator.
- **Header/Footer/Logo Removal**: Running headers, running footers, printed page numbers, and margin watermarks/logos (e.g. KCI logos) are automatically excluded.
- **Empty-Region Re-OCR**: Empty layout regions (such as footnotes obscured under logos) are re-cropped and re-OCR'd.

Example output:

```markdown
[p. 713]

은 기계적 반응이라고 폄하하였다. ... 동물 학대를 금지했고,[^4] ...

## 2. 피터 싱어(Peter Singer)의 동물윤리

피터 싱어(Peter Singer)는 ...

<!-- footnotes -->

[^4]: John Stuart Mill, On Liberty and the Subjection of Women, ...
```

### CLI Usage

Write Markdown to the default destination (`<input>.md`):

```bash
swift run apple-vision-ocr path/to/input.pdf --md-only
```

Specify a custom Markdown output path:

```bash
swift run apple-vision-ocr path/to/input.pdf --md-output output.md
```

Combine with multi-process split workers:

```bash
swift run apple-vision-ocr path/to/input.pdf --md-only --split-workers 4
```

Markdown output is mutually exclusive with `--output`, `--txt`, `--txt-only`, `--txt-output`, and `--page-breaks` (exits with code 1). It works seamlessly with `--split-workers`, `--page-range`, `--lang`, `--recognition-level`, `--render-scale`, `--no-language-correction`, and `--dry-run`.

Markdown takes longer and uses more memory than TXT because every page also goes through the layout model. Measured on an 18-core Apple Silicon Mac with 10 split workers: a 25-page paper took 3.7 s instead of 3.0 s and peaked at 2.7 GB instead of 1.5 GB; a 115-page thesis took 14.8 s instead of 12.6 s and peaked at 4.3 GB instead of 2.3 GB. In a single process the extra time is about 5%. If memory is tight, use fewer `--split-workers`.

### GUI Usage

In `VOCR.app`, select the **Markdown (layout)** / **Markdown (레이아웃 구분)** checkbox. Enabling Markdown automatically unchecks and disables the TXT, page separator, and Searchable PDF options.

### Layout Model Requirements

Layout analysis uses the CoreML `PP-DocLayoutV3` model (~90 MB, Apache-2.0, see `THIRD_PARTY_NOTICES.md`).
- In the packaged app, the compiled model is located at `VOCR.app/Contents/Resources/PPDocLayoutV3.mlmodelc`.
- The installed CLI at `~/.local/bin/apple-vision-ocr` is a symlink into `VOCR.app` so it automatically finds the model. If you copy only the CLI executable elsewhere, it cannot locate the model unless you set the environment variable:
  ```bash
  export APPLE_VISION_OCR_LAYOUT_MODEL=/path/to/PPDocLayoutV3.mlmodelc
  ```
- Developers building from source can download and compile the model by running:
  ```bash
  eval "$(scripts/fetch-layout-model.sh)"
  ```
  The `eval` command sets `APPLE_VISION_OCR_LAYOUT_MODEL` in the current shell so `swift run` and `.build/*/apple-vision-ocr` can find the compiled model.

### Known Limitations

- **Magazine-style multi-column layouts**: Multi-column pages where figures or tables span across columns may result in incorrect block reading order.
- **Footnote reference linking**: Only numeric references in the `n)` format are replaced inline within paragraph text. Unmatched, symbolic, or unnumbered footnotes are attached to the page marker line (e.g., `[p. 713] [^9]`).
- **Numbered lists at page bottom**: A numbered list at the very bottom of a page can occasionally be classified as footnotes.
- **Recovered logo text**: Text recovered from under a logo via re-crop OCR may contain recognition errors.
- **Uniform heading levels**: Heading levels are not distinguished by depth; all section headings are formatted as `##`.

## Korean And English OCR

The default language list is Korean and English:

```text
ko,en
```

You can set languages explicitly:

```bash
swift run apple-vision-ocr path/to/input.pdf --lang ko,en
swift run apple-vision-ocr english.pdf --lang en
```

Apple Vision's `fast` recognition mode does not support Korean on the tested
macOS version. For Korean or mixed Korean/English documents, use the default
`accurate` mode.

For English-only documents, `fast` mode can be used:

```bash
swift run apple-vision-ocr english.pdf \
  --lang en \
  --recognition-level fast
```

## Large Documents

For large OCR jobs, split workers can shorten wall time while keeping
page order in the final output:

```bash
swift run apple-vision-ocr large.pdf \
  --txt-only \
  --split-workers 12 \
  --render-scale 2.0
```

`--split-workers` (2-16) applies to text-only output, searchable PDF output, and
both together (`--txt`), with or without `--page-breaks`. For PDF, each worker produces a partial searchable PDF over its page
range and the parent merges them in page order, preserving the searchable text
layer. Note: in-process `--page-parallelism` alone does not speed things up —
Apple Vision serializes recognition within one process, so `--split-workers` is
the knob that actually uses multiple cores. On an 18-core machine ~12 workers is
the sweet spot.

If you only need part of a document:

```bash
swift run apple-vision-ocr large.pdf \
  --txt-only \
  --page-range 1-100
```

## Finder Quick Action

Install the app, CLI, and Finder Quick Action for the current macOS user:

```bash
scripts/install-vocr-quick-action.sh
```

Default install locations:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

After installation, select one or more PDF files in Finder, right-click, and
choose:

```text
Apple Vision OCR
```

The GUI follows the macOS language (English by default, Korean when the system language is Korean). The app lets you choose:

```text
Markdown (layout)
Extract TXT
Generate Searchable PDF
Insert page separators
```

The menu bar item shows progress while OCR runs. Closing the detail window keeps
the job running from the menu bar.

## Custom Install Paths

The app and binary install locations can be customized:

```bash
VOCR_APP_INSTALL_DIR="$HOME/Applications" \
VOCR_BIN_DIR="$HOME/.local/bin" \
scripts/install-vocr-quick-action.sh
```

The Finder workflow is always installed for the current user under:

```text
~/Library/Services/Apple Vision OCR.workflow
```

## Logs And Progress Files

Finder Quick Action logs:

```text
~/Library/Logs/vocr-quick-action.log
```

Menu bar progress snapshot:

```text
~/Library/Application Support/VOCR/progress/latest.json
```

## Troubleshooting

If `swift` is missing, install Xcode command line tools:

```bash
xcode-select --install
```

If Korean OCR with `--recognition-level fast` fails, remove `fast` mode or use
English-only input with `--lang en`.

If Finder does not show the Quick Action, run the installer again and then check
that the workflow exists:

```bash
ls "$HOME/Library/Services/Apple Vision OCR.workflow"
```

If running on macOS versions prior to macOS 26, use [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1).

If Markdown OCR fails with exit code 4 (`layout model not found`), compile the model and set its environment variable by running `eval "$(scripts/fetch-layout-model.sh)"` from a source checkout, or set `APPLE_VISION_OCR_LAYOUT_MODEL` to the path of `PPDocLayoutV3.mlmodelc`. Note that the CLI binary must be run through its installed symlink into `VOCR.app` or have `APPLE_VISION_OCR_LAYOUT_MODEL` set.

If OCR output already exists, choose a different `--output`, `--txt-output`, or `--md-output`
path. The CLI refuses to overwrite existing files.
