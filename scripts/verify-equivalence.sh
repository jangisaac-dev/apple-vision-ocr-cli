#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="${APPLE_VISION_OCR_BINARY:-$ROOT/.build/release/apple-vision-ocr}"
if (( $# > 1 )); then
    echo "Usage: $0 [INPUT.pdf]" >&2
    exit 2
fi
INPUT="${1:-$ROOT/.build/equivalence/equivalence-11.pdf}"
INPUT="${INPUT:A}"
WORKERS=4
if [[ ! -x "$BINARY" ]]; then
    echo "Missing release binary: $BINARY" >&2
    echo "Run: swift build -c release --product apple-vision-ocr" >&2
    exit 1
fi
if (( $# == 0 )) && [[ ! -f "$INPUT" ]]; then
    /usr/bin/python3 "$ROOT/scripts/make-bench-fixture.py" "$INPUT" 11
fi
if [[ ! -f "$INPUT" || "${INPUT:e:l}" != pdf ]]; then
    echo "INPUT must be an existing PDF" >&2
    exit 2
fi

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apple-vision-ocr-equivalence.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT INT TERM
overall_status=0
PAGES="$(/usr/bin/python3 -c '
import sys, AppKit, objc
AppKit.NSBundle.bundleWithPath_("/System/Library/Frameworks/PDFKit.framework").load()
d = objc.lookUpClass("PDFDocument").alloc().initWithURL_(AppKit.NSURL.fileURLWithPath_(sys.argv[1]))
raise SystemExit(print(d.pageCount()) if d else "cannot open input PDF")
' "$INPUT")"
echo "Input has $PAGES pages"

# cmp on two EMPTY files succeeds, so a run that recognized nothing at all would look equivalent.
require_nonempty() {
    if [[ ! -s "$1" ]]; then
        echo "FAIL: $2 produced no text at all" >&2
        overall_status=1
        return 1
    fi
    return 0
}

if "$BINARY" "$INPUT" --txt-only --txt-output "$RUN_DIR/single.txt" &&
   "$BINARY" "$INPUT" --txt-only --txt-output "$RUN_DIR/split.txt" --split-workers "$WORKERS" &&
   require_nonempty "$RUN_DIR/single.txt" "single-process TXT" &&
   cmp -s "$RUN_DIR/single.txt" "$RUN_DIR/split.txt"; then
    echo "PASS: TXT output matches byte-for-byte"
else
    echo "FAIL: TXT output differs" >&2
    overall_status=1
fi

if "$BINARY" "$INPUT" --txt-only --txt-output "$RUN_DIR/single-breaks.txt" --page-breaks &&
   "$BINARY" "$INPUT" --txt-only --txt-output "$RUN_DIR/split-breaks.txt" --page-breaks --split-workers "$WORKERS" &&
   require_nonempty "$RUN_DIR/single-breaks.txt" "single-process page-break TXT" &&
   cmp -s "$RUN_DIR/single-breaks.txt" "$RUN_DIR/split-breaks.txt"; then
    echo "PASS: TXT page-break output matches byte-for-byte"
else
    echo "FAIL: TXT page-break output differs" >&2
    overall_status=1
fi

if "$BINARY" "$INPUT" --output "$RUN_DIR/single.pdf" &&
   "$BINARY" "$INPUT" --output "$RUN_DIR/split.pdf" --split-workers "$WORKERS" &&
   /usr/bin/python3 - "$RUN_DIR/single.pdf" "$RUN_DIR/split.pdf" "$PAGES" <<'PY'
import sys
import AppKit
import objc

AppKit.NSBundle.bundleWithPath_("/System/Library/Frameworks/PDFKit.framework").load()
PDFDocument = objc.lookUpClass("PDFDocument")

def pages(path):
    document = PDFDocument.alloc().initWithURL_(AppKit.NSURL.fileURLWithPath_(path))
    if document is None:
        raise SystemExit("failed to open PDF: " + path)
    return [str(document.pageAtIndex_(i).string() or "") for i in range(document.pageCount())]

single = pages(sys.argv[1])
split = pages(sys.argv[2])
# A bare list comparison passes when BOTH sides are empty or all-blank, which would make a
# totally broken OCR run look equivalent. Require real recognized text before comparing.
expected_pages = int(sys.argv[3])
if len(single) != expected_pages:
    raise SystemExit("single-process page count {} != input page count {}".format(len(single), expected_pages))
if not any(page.strip() for page in single):
    raise SystemExit("single-process PDF carries no extractable text at all")
if single != split:
    different = next((i + 1 for i, pair in enumerate(zip(single, split)) if pair[0] != pair[1]), None)
    if different is None:
        raise SystemExit("PDF page count differs: {} != {}".format(len(single), len(split)))
    raise SystemExit("PDF extracted text differs on page {}".format(different))
PY
then
    echo "PASS: PDF extracted text matches page-by-page"
else
    echo "FAIL: PDF extracted text differs" >&2
    overall_status=1
fi

if (( overall_status == 0 )); then
    echo "PASS: single and split outputs are equivalent (workers=$WORKERS)"
else
    echo "FAIL: equivalence verification failed" >&2
fi
exit "$overall_status"
