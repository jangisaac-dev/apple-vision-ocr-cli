# OCR Speed Alternatives Check

Date: 2026-05-17
Machine context: local macOS, repo `<repo>`

## Question

The current OCR path still feels similar in speed. Check whether this is caused by depending on Apple Vision, and whether another OCR engine would be a better direction.

## Current Implementation Findings

- The app uses Vision framework `VNRecognizeTextRequest`, not VisionKit UI APIs.
- The CLI exposes `--recognition-level accurate|fast`, `--page-parallelism`, and `--render-scale`.
- The default page parallelism is now 8 in both CLI parsing and core `OCRJobOptions`, so the default Korean accurate path uses multiple page workers unless the user explicitly sets `--page-parallelism 1`.
- The selectable page parallelism range is now 1-16. In the 100-page Korean benchmark below, 16-way parallelism started more pages at once but did not beat 8-way parallelism end-to-end.
- The VOCR GUI does pass `OCRJobParallelism.default` and can update the limiter while running.
- Selected PDFs are intentionally processed one file at a time; the current parallelism is page-level within the active PDF only.
- The page scheduler now uses a bounded worker pool instead of one-off per-page submissions, so worker threads continue pulling pages until the active PDF is exhausted while the shared limiter enforces the selected cap.
- The Korean-safe speed path is now `accurate` recognition with page worker parallelism and configurable render scale. This avoids Apple Vision `fast` for Korean and reduces the amount of image data sent into Vision.

## Local Benchmark

Test file:

- `Samples/sample.pdf` repeated into `.build/bench/sample-10.pdf`
- 10 image-only pages, simple English text

Commands and results:

| Path | Command shape | Time | Text result |
| --- | --- | ---: | --- |
| Apple Vision accurate | `.build/release/apple-vision-ocr .build/bench/sample-10.pdf --txt-output ... --page-breaks` | 2.08s | matched sample text |
| Apple Vision fast, English sample | same plus `--lang en --recognition-level fast` | 0.41s | matched sample text |
| Apple Vision fast, English sample, page parallelism 4 | same plus `--lang en --recognition-level fast --page-parallelism 4` after implementation | 0.33s | matched sample text |
| Apple Vision fast, Korean book page | `거꾸로 읽는 로마서` page 1 with `--lang ko,en --recognition-level fast` | 0.17s | failed: only `ea / In / Backwards` |
| Apple Vision accurate, Korean book page | same page with `--lang ko,en --recognition-level accurate` | 0.46s | passed: recognized Korean title/author text |
| Apple Vision accurate, Korean page, render scale 2.0 | same page with `--lang ko,en --recognition-level accurate --render-scale 2.0` after implementation | 0.37s | passed: recognized Korean title/subtitle/author text |
| Apple Vision accurate, Korean-safe balanced render | same page with `--lang ko,en --recognition-level accurate --render-scale 1.5` after implementation | 0.35s | passed: recognized Korean title/subtitle/author text |
| Apple Vision accurate, compact draft render | same page with `--lang ko,en --recognition-level accurate --render-scale 1.25` after implementation | 0.33s | passed title/subtitle/author, but smaller side text changed more |
| Tesseract one page | `tesseract .build/bench/sample-10-page1.png stdout -l eng+kor` | 0.17s | matched sample text, spacing differed |
| Tesseract 10 pages OCR only, parallel 4 | `xargs -P 4 tesseract ... -l eng+kor txt` | 0.58s | matched sample text |
| Poppler render for Tesseract input | `pdftoppm -r 144 -png .build/bench/sample-10.pdf ...` | 1.22s | render only |

Notes:

- Vision requests failed inside the Codex sandbox with a generic Foundation Objective-C error; the benchmark above was run outside the sandbox after approval.
- On the simple English fixture, Apple Vision `fast` is the fastest measured path end-to-end.
- Apple Vision reports `ko-KR` as supported for `accurate` but not for `fast` on this macOS version. The app now rejects or blocks fast mode for Korean/default `ko,en` OCR to avoid garbage output.
- On the one-page Korean cover sample, lowering render scale produced only a small elapsed-time gain. Treat `1.5` as a safe operator knob, not as proof that render scale alone solves long-document throughput. A multi-page Korean benchmark is still required.
- Tesseract is locally installed at `/opt/homebrew/bin/tesseract` with `eng` and `kor` language data available.
- `ocrmypdf` is not currently installed on PATH.

## 100-Page Korean Benchmark

Test file:

- Source: `local Korean theology PDF sample`
- Split output: `.build/bench/romans-100-20260517/romans-first-100.pdf`
- Page count: 100
- Existing text layer check: `pdftotext -f 1 -l 5` produced only form-feed characters, so text reuse is not available.

Commands and results:

| Path | Command shape | Time | Quality note |
| --- | --- | ---: | --- |
| Apple Vision accurate, pp4, render 1.5, TXT | `apple-vision-ocr ... --txt-only --page-parallelism 4 --render-scale 1.5` | 77.27s | good Korean text on sampled pages |
| Apple Vision accurate, pp8, render 1.5, TXT | `apple-vision-ocr ... --txt-only --page-parallelism 8 --render-scale 1.5` | 75.42s | good Korean text on sampled pages |
| Apple Vision accurate, pp8, render 1.25, TXT | `apple-vision-ocr ... --txt-only --page-parallelism 8 --render-scale 1.25` | 76.35s | slightly different/sometimes worse small text; no speed win |
| Apple Vision accurate, pp8, render 2.0, TXT | `apple-vision-ocr ... --txt-only --page-parallelism 8 --render-scale 2.0` | 75.95s | best quality-safe default |
| Apple Vision accurate, pp8, render 1.5, searchable PDF | `apple-vision-ocr ... --output ... --page-parallelism 8 --render-scale 1.5` | 76.66s | searchable PDF writing is not the bottleneck |
| Apple Vision accurate, pp16, render 2.0, TXT | `.build/release/apple-vision-ocr ... --txt-only --page-parallelism 16 --render-scale 2.0` | 76.78s | no end-to-end win over pp8 |
| Poppler JPEG 72dpi + Tesseract kor+eng pp8, TXT | `pdftoppm -r 72 -jpeg`, then `xargs -P 8 tesseract ... -l kor+eng --psm 6 txt` | 25.42s total | much faster, but many Korean/English mixed OCR errors |
| Poppler JPEG 100dpi + Tesseract kor+eng pp8, TXT | `pdftoppm -r 100 -jpeg`, then `xargs -P 8 tesseract ... -l kor+eng --psm 6 txt` | 26.55s total | still many OCR errors; not default-quality safe |
| Poppler JPEG 150dpi + Tesseract kor+eng pp8, TXT | `pdftoppm -r 150 -jpeg`, then `xargs -P 8 tesseract ... -l kor+eng --psm 6 txt` | 33.00s total | better than 100dpi but still below Apple Vision quality |
| Poppler JPEG 100dpi + Tesseract kor+eng pp8, searchable PDF | render + `tesseract ... pdf` + `pdfunite` | 27.45s total | fast searchable PDF, but same quality caveat |

Decision:

- Keep Apple Vision accurate as the quality-safe default.
- Raise the default page parallelism to 8 because it is the fastest quality-safe Apple Vision setting measured on the 100-page Korean PDF.
- Allow manual page parallelism up to 16 for operator experiments, but do not make 16 the default because it was slower than 8 end-to-end.
- Do not make Tesseract the default backend. It is a useful draft-speed candidate, but the sampled Korean pages contain enough recognition errors that it does not meet the quality bar for normal VOCR output.

## Alternative Engines

Follow-up model-candidate benchmark:

- `docs/benchmarks/2026-05-17-ocr-model-candidates.md`

### 1. Stay on Apple Vision, expose real speed knobs

This is the lowest-risk direction.

- Add CLI/page-batch support for `--page-parallelism N` so CLI and GUI behave consistently.
- Keep `fast` recognition available only for supported language sets. For the current Korean-default VOCR workflow, block fast mode and use page parallelism with accurate mode instead.
- Consider a language-correction toggle. The current recognizer always sets `usesLanguageCorrection = true`, which can help quality but may add work.
- Use `--render-scale 1.5` as the first Korean-safe speed setting before trying external OCR engines. `1.25` is available for quick draft extraction where users accept more quality risk.

Expected outcome:

- Fastest near-term improvement without changing packaging, privacy, searchable-PDF writer, or macOS app boundary.
- The quality tradeoff must be tested on real Korean theology PDFs, because the sample file is too simple.

### 2. Add Tesseract/OCRmyPDF as an optional engine

This is feasible, but not an obvious speed win from the local benchmark.

Pros:

- Tesseract can output TXT, TSV/HOCR, and searchable PDF.
- OCRmyPDF provides mature PDF repair, existing-text handling, rasterizer choice, and batch patterns.
- Tesseract is already installed locally with Korean and English data.

Cons:

- Adds external binary dependencies and version drift.
- Requires separate PDF rendering/merge/text-layer integration if not delegating everything to OCRmyPDF.
- In the local English test, Tesseract plus rendering was not faster than Vision `fast`.
- OCRmyPDF is not installed yet, so a real OCRmyPDF benchmark still needs setup.

Best use:

- Optional fallback engine for documents where Apple Vision quality is poor, not the default speed path.

### 3. Add PaddleOCR / PP-OCRv5 as a separate experimental backend

This is a larger product change.

Pros:

- Modern open-source OCR pipeline with Korean-specific recognition models.
- Potentially better on difficult multilingual scans after tuning.

Cons:

- Requires Python/uv environment, model downloads, and a new engine adapter.
- Searchable PDF output still has to be generated by our writer or another PDF layer.
- Official PP-OCRv5 performance references are not directly comparable to local Apple Silicon; CPU full-pipeline numbers are not clearly faster than our current Vision fast path.

Best use:

- Experimental quality comparison on a small fixed Korean PDF corpus, not an immediate replacement.

### 4. Cloud/commercial OCR

Examples: Google Document AI/Vision, AWS Textract, Azure AI Document Intelligence, Naver CLOVA OCR, Upstage Document AI, ABBYY.

Pros:

- Can be better for messy scanned documents, layout-heavy PDFs, tables, and handwriting.
- Server-side parallelism can hide local CPU limits.

Cons:

- Privacy and cost tradeoff.
- Network dependency.
- Searchable-PDF preservation still needs integration work unless the provider returns a ready PDF.

Best use:

- Optional manual mode for non-private documents where quality matters more than local-only operation.

## Recommendation

Do not replace Apple Vision yet. The current evidence says the next practical work is:

1. Add CLI `--page-parallelism N` so the already-written page concurrency is usable outside VOCR. Implemented on 2026-05-17; default raised to 8 and maximum raised to 16 after the 100-page Korean benchmark.
2. Add a visible speed mode in VOCR that maps to `recognitionLevel = .fast`. Implemented on 2026-05-17, then guarded on 2026-05-17 after confirming fast mode does not support Korean.
3. Add a Korean-safe speed control that keeps `recognitionLevel = .accurate` and lowers PDF render scale. Implemented on 2026-05-17 as CLI `--render-scale` and VOCR `한국어 속도/품질`.
4. Replace per-page ad hoc task submission with a bounded page worker pool so available OCR slots stay filled more consistently. Implemented on 2026-05-17.
5. Add a benchmark harness with a real Korean multi-page PDF corpus and compare:
   - Vision accurate
   - Vision accurate with page parallelism 2/4/8 and render scale 2.0/1.5/1.25 for Korean PDFs
   - Vision fast only for supported non-Korean language sets
   - Tesseract direct
   - OCRmyPDF if installed in a repo-local uv environment
   - PaddleOCR only if the first two do not meet the target

This keeps the current Swift-native local app intact while giving us measured exit criteria for moving to another engine.

## Sources Checked

- Apple Developer Documentation: `VNRequestTextRecognitionLevel`
- Tesseract tessdoc: command-line usage and searchable PDF output
- OCRmyPDF 17.4.2 docs: OCR modes, rasterizer choices, performance notes, batch processing
- PaddleOCR PP-OCRv5 docs: pipeline modules and reference performance tables
