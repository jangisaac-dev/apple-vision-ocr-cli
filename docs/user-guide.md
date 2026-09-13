# Apple Vision OCR User Guide

English | [한국어](user-guide.ko.md)

Apple Vision OCR turns image-only PDF pages into searchable PDFs, plain text
files, or both. It uses Apple's built-in Vision framework, so it runs locally on
macOS and does not upload your documents.

## What You Need

- macOS 13 or later.
- A PDF file. Image-only scans are the main use case.
- For the release package: an Apple Silicon Mac. Nothing else.
- For building from source: Xcode command line tools or Xcode.

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

The app lets you choose:

```text
TXT 추출
Searchable PDF 생성
Page 구분자 넣기
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

If OCR output already exists, choose a different `--output` or `--txt-output`
path. The CLI refuses to overwrite existing files.
