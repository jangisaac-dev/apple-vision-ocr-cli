# Apple Vision OCR vs OwlOCR CLI Benchmark

Date: 2026-05-16
Machine context: local macOS, repo `<repo>`

## Rules

- Apple Vision OCR and OwlOCR were not run at the same time.
- Commands were run with short time limits where OwlOCR was known to hang.
- Quality is measured only with evidence available from generated/extracted text. This is not a full ground-truth OCR accuracy score.

## Test Input

| Input | Pages | Original Extractable Text |
| --- | ---: | ---: |
| `Samples/sample.pdf` | 1 | 0 chars |

## Results

| Engine / Path | Command Shape | Time | Output | Extracted Text Evidence | Result |
| --- | --- | ---: | --- | --- | --- |
| Apple Vision OCR CLI | `.build/release/apple-vision-ocr Samples/sample.pdf --output .../sample.apple.pdf` | 0.40s | `sample.apple.pdf` | 53 chars: `HELLO OCR SAMPLE / APPLE VISION TEXT / COPYABLE AFTER OCR` | Passed |
| Apple Vision OCR CLI, same file used for Quick Action timing | `.build/release/apple-vision-ocr .../quick-action-2026-05-16-2150/sample.pdf --output .../sample.apple.pdf` | 0.41s | `sample.apple.pdf` | 53 chars: `HELLO OCR SAMPLE / APPLE VISION TEXT / COPYABLE AFTER OCR` | Passed |
| Installed Apple Vision OCR CLI with TXT page breaks | `~/.local/bin/apple-vision-ocr Samples/sample.pdf --output .../sample_ocr.pdf --txt-output .../sample.txt --page-breaks` | 0.39s | `sample_ocr.pdf`, `sample.txt` | TXT starts with `===== Page 1 =====` and contains the 53 chars above | Passed |
| OwlOCR app CLI, repo PDF | `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --input Samples/sample.pdf --output ... --silent --force` | 20s timeout | none | none | Timed out |
| OwlOCR app CLI, Downloads PDF safe zone | same CLI after copying PDF to `~/Downloads/.OwlOCR_Workplace/...` | 60s timeout | none | none | Timed out |
| OwlOCR app CLI, Downloads PDF text mode | `OwlOCR --cli --force --input <safe-zone-pdf>` | 60s timeout | none | none | Timed out |
| OwlOCR app CLI, container PNG text mode | `OwlOCR --cli --input ~/Library/Containers/JonLuca-DeCaro.OwlOCR/Data/tmp/<page>.png` | 60s timeout | none | none | Timed out |
| OwlOCR native bundled binary | `/Applications/OwlOCR.app/Contents/Resources/native/owlocr --input <page>.png` | 0.01s | none | none | Abnormal exit |
| OwlOCR Quick Action: `OwlOCR - PDF로 변환.workflow` via `automator` | `automator -i .../sample.pdf ~/Library/Services/OwlOCR - PDF로 변환.workflow` | 180s timeout | none | none | Timed out after launching OwlOCR |
| OwlOCR Quick Action: `OwlOCR - Page 추출.workflow` via `automator` | `automator -i .../sample.pdf ~/Library/Services/OwlOCR - Page 추출.workflow` | 180s timeout | none | progress JSON stayed at `Processing page 1 of 1` | Timed out after launching OwlOCR |

## OwlOCR Quick Action Findings

Registered Quick Actions under `~/Library/Services` use these OwlOCR execution patterns:

| Quick Action | Implementation | OwlOCR Path |
| --- | --- | --- |
| `OwlOCR - 텍스트만 추출.workflow` | AppleScript copies the input to `~/Downloads/.OwlOCR_Workplace/<uuid>/`, runs stdout OCR, writes `<input>.txt`. | `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --force --input <tmpInput>` |
| `OwlOCR - PDF로 변환.workflow` | AppleScript copies the input to `~/Downloads/.OwlOCR_Workplace/<uuid>/`, writes a temporary OCR PDF, then moves it back. | `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --force --input <tmpInput> --output <tmpOutput> --silent` |
| `OwlOCR - 텍스트 및 PDF 생성.workflow` | Runs the PDF path first, then runs stdout text OCR on the same temporary input. | Same as above |
| `OwlOCR - Page 추출.workflow` | Inline Python renders PDF pages to PNG, copies each PNG into OwlOCR container tmp, runs stdout OCR sequentially, and writes `===== Page N =====` sections. | `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --input <tmpPng>` |
| `OwlOCR - Page 추출2.workflow` | Similar to Page 추출, but uses `ThreadPoolExecutor(max_workers=2)`. | Same as above |

The direct terminal reproductions of these Quick Action command shapes currently do not complete. The app wrapper repeatedly prints:

```text
Unable to set login item: The operation couldn't be completed. Operation not permitted
```

Running the registered Quick Actions through `automator` does launch the actual workflow code. Evidence from the process table during the timed run:

- `OwlOCR - PDF로 변환.workflow` launched `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --force --input ~/Downloads/.OwlOCR_Workplace/.../sample.pdf --output .../sample_ocr.pdf --silent`, but no output was created after 180 seconds.
- `OwlOCR - Page 추출.workflow` launched inline Python, `OwlOCRProgressHelper`, and `/Applications/OwlOCR.app/Contents/MacOS/OwlOCR --cli --input ~/Library/Containers/JonLuca-DeCaro.OwlOCR/Data/tmp/...page_0001.png`. Its progress JSON stayed at `status=ocr_running`, `message=Processing page 1 of 1`, `completed_pages=0` until the 180 second timeout.

The older iCloud workflow log at `~/Library/Logs/pdf-extract-kit.log` shows successful OwlOCR text extraction in January 2026 through `~/.config/opencode/tools/pdf_to_txt_owlocr.py`, but that script path is not present now. Current registered Services are different from that older logged workflow.

## Interpretation

Apple Vision OCR CLI is currently benchmarkable from terminal and produced searchable text on the sample.

OwlOCR cannot be fairly scored for speed or OCR quality from the current terminal automation path because every registered command shape either timed out or exited abnormally without output. The next valid OwlOCR comparison should first restore a working non-interactive OwlOCR CLI path, or run the Quick Action manually from Finder and compare the produced output artifact.
