# Vision Pipeline Render-Ahead Benchmark

Date: 2026-05-29

## Goal

Improve Apple Vision `accurate` OCR throughput while preserving the quality path:

- source: `~/Documents/거꾸로 읽는 로마서.pdf`
- pages: 398
- output: `--txt-only`
- render scale: `--render-scale 2.0`
- recognition level: default `accurate`

## Baseline

Historical monolithic worker-pool result from `/tmp/ocr-bench/run-2.0-pp16.log`:

| Pipeline | Settings | real | user | sys |
| --- | --- | ---: | ---: | ---: |
| monolithic render + Vision worker | pp16, queue N/A | 229.48s | 307.24s | 10.34s |

Baseline text output:

- `/tmp/ocr-bench/romans-2.0-pp16.txt`
- SHA-256: `f10dd05e4a5ae6ce94885f938b47dd6d838ebf55d442b3b3236face6e04cb693`

## Tested Candidates

All candidates produced the same text hash as the baseline:

`f10dd05e4a5ae6ce94885f938b47dd6d838ebf55d442b3b3236face6e04cb693`

| Candidate | Settings | real | Delta vs baseline |
| --- | --- | ---: | ---: |
| decoupled render/Vision | pp16, render producers 8, queue 12 | 218.54s | -10.94s (-4.8%) |
| decoupled render/Vision | pp12, render producers 8, queue 12 | 224.54s | -4.94s (-2.2%) |
| decoupled render/Vision | pp24, render producers 8, queue 12 | 222.61s | -6.87s (-3.0%) |
| decoupled render/Vision | pp16, render producers 4, queue 12 | 221.98s | -7.50s (-3.3%) |
| decoupled render/Vision | pp16, render producers 8, queue 32 | 217.28s | -12.20s (-5.3%) |
| decoupled render/Vision | pp16, render producers 8, queue 64 | 218.89s | -10.59s (-4.6%) |
| final default | pp16, render producers 8, queue 32 | 215.61s | -13.87s (-6.0%) |

Final default output:

- `/private/tmp/ocr-speed-goal/romans-decoupled-final-default.txt`
- SHA-256: `f10dd05e4a5ae6ce94885f938b47dd6d838ebf55d442b3b3236face6e04cb693`

## Decision

The fastest single-process quality-preserving path is the decoupled render/Vision pipeline with:

- bounded signaled render-ahead queue;
- default queue capacity 32;
- render producer count 8 for this 398-page file;
- normal user-facing max page parallelism 16.

Raising page parallelism above 16 did not help on this file, and reducing render producers to 4 was slower. Queue 64 was also slower than queue 32.

## 40%+ Target Follow-Up

The single-process pipeline improvement is not enough for a 40% wall-time target. The successful approach is multi-process page-range splitting:

| Candidate | Settings | real | Delta vs baseline |
| --- | --- | ---: | ---: |
| manual 4-process split | 4 chunks, pp4 per process, render 2.0 | 63.79s | -165.69s (-72.2%) |
| implemented `--split-workers` | `--split-workers 4 --page-parallelism 4 --render-scale 2.0` | 66.43s | -163.05s (-71.1%) |

The implemented `--split-workers` path does not rewrite chunk PDFs. It runs child processes against the original PDF with non-overlapping `--page-range` values, then joins text outputs in order. This preserved the baseline text exactly:

- baseline SHA-256: `f10dd05e4a5ae6ce94885f938b47dd6d838ebf55d442b3b3236face6e04cb693`
- split-workers SHA-256: `f10dd05e4a5ae6ce94885f938b47dd6d838ebf55d442b3b3236face6e04cb693`

The earlier PDFKit chunk-rewrite variant ran in `68.51s`, but it changed OCR output and was rejected.

## Implementation Notes

`SearchablePDFPipeline` now separates render producers from Vision consumers using an `NSCondition`-backed bounded queue. This fixes the previous polling queue regression and avoids consumer hang after producers finish.

Two private environment variables remain available for future measurement without exposing new CLI options:

- `APPLE_VISION_OCR_RENDER_PRODUCERS`
- `APPLE_VISION_OCR_QUEUE_CAPACITY`

New CLI options added for the successful speed path:

- `--page-range START-END` for text-only OCR over a 1-based page range.
- `--split-workers N` for text-only multi-process OCR over non-overlapping page ranges.

## Searchable PDF Follow-Up Decision

Searchable PDF split-workers are deferred for now.

The likely implementation shape is similar to the text-only path, but the merge step is materially harder:

1. Run each child process against the original PDF, not a rewritten chunk PDF.
2. Give each child a non-overlapping page range.
3. Write one searchable PDF per range.
4. Merge the child PDFs in page order.
5. Verify page count, page order, page geometry, and extracted searchable text.

This should not be enabled by simply relaxing `--page-range` validation for PDF output. The writer currently emits only the selected pages it receives, and PDF outputs are not byte-for-byte comparable because metadata and object ordering can change. Validation needs `pdfinfo`, `pdftotext`, page dimensions, and sampled visual/geometry checks.

The existing searchable PDF path was smoke-tested outside the Codex sandbox on `Samples/sample.pdf` and `Samples/sample_ocr.pdf`. Both completed and produced extractable text. Inside the Codex sandbox, CoreGraphics PDF output failed with `Foundation._GenericObjCError error 0`, so searchable PDF runtime checks should be run outside the sandbox when validating this path.
