# Current Status

Updated: 2026-09-13 (v1.1.0)

## Current Objective

The product goal is not to force Apple Vision `fast` mode onto Korean OCR.
Apple Vision `fast` does not support `ko-KR` on the tested macOS version and produces unusable text.

The current goal is:

1. Keep Korean/default OCR on Apple Vision `accurate`.
2. Prevent unsupported fast-mode Korean output.
3. Improve Korean OCR throughput through safe knobs:
   - multi-process split workers for large documents (text-only, searchable PDF, or both);
   - lower PDF render scale for optional speed-balanced runs.
4. Note on in-process parallelism: in a SINGLE process Apple Vision serializes recognition, so `--page-parallelism` does not raise throughput there (it pins ~1-2 cores). Multi-process `--split-workers` is the knob that actually uses the machine. Corrected 2026-09-09: this does NOT extend to split children — forcing child `pp=1` at 12 workers measured 10% SLOWER (54.42s vs 49.53s) while saving 9% RSS, so `pp` still buys render/recognition overlap inside each worker.

## Implemented

- CLI and core job validation reject unsupported `fast` recognition language sets such as default `ko,en`.
- VOCR labels Vision fast mode as English-only and blocks it for the current Korean-default workflow.
- CLI supports `--page-parallelism`, with 1-16 selectable page workers and default 8.
- CLI now supports `--render-scale 1.25|1.5|2.0`.
- VOCR now exposes `한국어 속도/품질`:
  - `품질 우선 (2.0x)`
  - `한국어 속도 균형 (1.5x)`
  - `빠른 초안 (1.25x)`
- The core page scheduler uses a bounded worker pool so available page slots stay filled until the active PDF is exhausted.
- The Apple Vision page pipeline now decouples PDF rendering from Vision recognition with a signaled bounded render-ahead queue. On the 398-page Korean reference PDF at render 2.0 + accurate, the final single-process default measured `real 215.61s` versus the earlier pp16 baseline `real 229.48s`, with identical text output hash.
- CLI text-only OCR now supports `--page-range START-END` and `--split-workers N`. The 398-page Korean reference PDF measured `real 66.43s` with `--split-workers 4 --page-parallelism 4 --render-scale 2.0`, while preserving the baseline text SHA-256 exactly.
- `--split-workers` upper bound raised from 8 to 16 (2026-06-12). On an 18-core machine the practical sweet spot is ~12 workers; in-process `--page-parallelism` gives no speedup because Apple Vision serializes recognition per process (measured: dense 24-page PDF stays ~45s for pp1/pp8/pp16, peak CPU ~199% = 2 cores; `--split-workers 12` reaches ~17 cores).
- VOCR GUI (the Finder right-click path) now uses multi-process parallelism (2026-06-13). The split/merge logic was extracted into shared `Sources/AppleVisionOCRCore/SplitProcessOCRRunner.swift` (spawns `apple-vision-ocr` page-range children, parses their "Completed page" stderr lines for live progress, merges PDFs / concatenates text, supports cancel via `OCRJobControl` and pause via SIGSTOP/SIGCONT). Both CLI runners are now thin wrappers over it. `OCRJobController` uses the shared runner when the worker count is >= 2, and falls back to the in-process pipeline for worker count 1 or when the CLI binary cannot be located. (Updated 2026-09-13: originally combined TXT+PDF also fell back to in-process; since 2026-09-10 (`436fddc`) combined output splits too via `SplitProcessOCRRunner.Output.searchablePDFAndText`.) The GUI "동시 OCR 페이지 수" stepper became "동시 워커 프로세스 수" (auto-default ~= activeProcessorCount*2/3, capped 16). `apple-vision-ocr` is now bundled inside `VOCR.app/Contents/MacOS/` (package-vocr-app.sh); the GUI locates it via `VOCR_CLI_PATH` > bundle sibling > `~/.local/bin` > PATH. A `VOCR_HEADLESS=1` env seam auto-runs a default searchable-PDF job for end-to-end testing.
- Searchable PDF split-worker support is now IMPLEMENTED (2026-06-12), following the previously-deferred safe design. New `Sources/AppleVisionOCRCLI/ChunkedPDFOCRRunner.swift` runs child processes over non-overlapping page ranges (`--output chunk.pdf --page-range A-B`), each producing a per-range searchable PDF via the proven single-process pipeline, then the parent merges them in page order. The merge uses CoreGraphics `CGContext.drawPDFPage` (the same mechanism `PDFTextOverlayWriter` already uses to copy original pages), NOT the rejected PDFKit chunk-rewrite approach, so the invisible OCR text layer is preserved unchanged. The `--split-workers` / `--page-range` validation was relaxed from "text-only" to "single output mode" (text-only XOR PDF-only); simultaneous text+PDF (`--txt`) and `--page-breaks` remain rejected. Routing: `CommandRunner` sends `splitWorkers` + a PDF output URL to `ChunkedPDFOCRRunner`, otherwise to `ChunkedTextOCRRunner`. (Updated 2026-09-13: both restrictions have since been lifted — `--page-breaks` on 2026-06-13, combined text+PDF on 2026-09-10. `CommandRunner` now sends PDF+TXT to `SplitProcessOCRRunner` with `.searchablePDFAndText`, PDF-only to `ChunkedPDFOCRRunner`, and TXT-only to `ChunkedTextOCRRunner`.)
- VOCR selected-file list is a fixed-height (80 pt), non-wrapping `NSTextView.scrollableTextView()` that scrolls vertically and horizontally (2026-09-13). The old wrapping label grew with the file count and pushed the progress, log, and buttons out of the fixed 580 pt window. Verified by installing with `scripts/install-vocr-quick-action.sh` and opening `~/Applications/VOCR.app` with 30 long-path PDFs. Modification guide: `docs/architecture-and-modification-guide.md`.
- Fixed (2026-09-13): `--page-range` was silently ignored under `--split-workers` — the split runner always planned chunks over the whole document (reproduced: 5-page PDF, `--page-range 2-3 --split-workers 2` produced pages 1-5). `SplitProcessOCRRunner.run` now takes `pageRange`, plans chunks over the selected pages, and rejects a range past the last page; all three CLI split routes pass it. Regression test: `testRunSplitsOnlyTheRequestedPageRange`.
- Installer (2026-09-13): `scripts/install-vocr-quick-action.sh` installs a prebuilt `VOCR.app` when one sits next to it (release package) and builds only from a checkout; it replaces the app via a staged copy, strips quarantine, installs the CLI from the app bundle, and bakes `VOCR_APP` into the Finder workflow so custom `VOCR_APP_INSTALL_DIR` installs launch the right app (previously the wrapper always opened `~/Applications/VOCR.app`).
- Release packaging (2026-09-13): `scripts/make-release-package.sh` builds `.release/VOCR-<version>-macos-<arch>.zip` (app, installer, `Install.command`, `README.txt`, `LICENSE`) with a SHA-256 file. v1.1.0 ships arm64 only; the app is ad-hoc signed and not notarized.

## Fresh Verification

- 2026-05-18: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test` passed: 75 tests, 0 failures.
- 2026-05-18: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release` passed after rerunning outside the Codex sandbox because SwiftPM manifest sandboxing failed with `sandbox-exec: sandbox_apply: Operation not permitted`.
- 2026-05-29: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter SearchablePDFPipelineParallelismTests` passed: 2 tests, 0 failures.
- 2026-05-29: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release` passed after rerunning outside the Codex sandbox.
- 2026-05-29: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test` passed after merge: 80 tests, 0 failures.
- 2026-05-29: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release` passed after merge.
- 2026-05-29: Full 398-page reference run passed with render 2.0 + accurate + pp16, text-only output, `real 215.61`, and SHA-256 matching the earlier pp16 baseline text output.
- 2026-05-29: Full 398-page split-worker reference run passed with render 2.0 + accurate + `--split-workers 4 --page-parallelism 4`, text-only output, `real 66.43`, and SHA-256 matching the earlier pp16 baseline text output.
- 2026-05-29: Split-worker output was compared with the baseline using SHA-256, `cmp`, and `wc -l -c`; both files were `11446` lines and `643531` bytes.
- 2026-06-12: `swift build -c release` and `swift test` passed: 86 tests, 0 failures (Apple M5 Pro, 18 cores). +3 tests for the raised split-workers bound and PDF-only split parsing.
- 2026-06-12: Searchable PDF split path benchmarked on a generated dense 24-page Korean+English PDF: single-process `--page-parallelism 12` = `46.28s`; `--split-workers 12` = `7.05s` (6.6x). Both outputs: 24 pages, identical extracted text length (73151 chars via PDFKit) — searchable text layer preserved by the merge.
- 2026-06-12: Merge order/completeness verified on a 23-page PDF with per-page distinguishable markers, split `5,5,5,4,4` (non-even, exercises the remainder branch). Walking pages with PDFKit confirmed each merged page carries its own OCR marker in order, with no drops, duplicates, or reordering.
- 2026-06-12 verification boundary: tested on generated PDFs with no page rotation and no pre-existing text layer (matches scanned-image inputs). Rotated pages and the existing-text rasterization branch are inherited from the proven single-process pipeline but were not independently re-exercised in the split path.
- 2026-06-13: `swift build -c release` and `swift test` passed: 91 tests, 0 failures.
- 2026-06-13: CLI now allows `--split-workers` together with `--page-breaks` (previously rejected), matching the GUI. The CLIOptions guard against the combination was removed; `ChunkedTextOCRRunner` passes `options.includePageBreaks` to `SplitProcessOCRRunner`. It resolves to text-only + page-divided output (page-breaks already require text output, split requires a single output mode). Verified: `--txt-only --page-breaks --split-workers 4` on a 9-page PDF produced all 9 `===== Page N =====` markers in order. Test `testSplitWorkersRejectPageBreaks` replaced with `testSplitWorkersAllowPageBreaksWithTextOnly`.
- 2026-06-13: Fixed a regression where the GUI "Page 구분자 넣기" (page-divided TXT) lost its `===== Page N =====` markers. Root cause: page-divided TXT is single output mode, so it routed through the split path, but `SplitProcessOCRRunner` did not pass `--page-breaks` to its page-range child processes. Fix: thread an `includePageBreaks` flag through `SplitProcessOCRRunner.run` → child args (`--page-breaks` for `.text`); `OCRJobController` passes `selection.includesPageBreaks`. Children emit absolute page numbers in their range, so the concatenated output is correct and still parallel. Verified via the headless seam (`VOCR_HEADLESS=txt-pagebreaks`): 7-page PDF produced all 7 markers in order. (The CLI still rejects `--split-workers` + `--page-breaks`; only the GUI path was affected/fixed.)
- 2026-06-13: VOCR is now a menu bar agent — `LSUIElement` added to the app Info.plist (package-vocr-app.sh) and all `NSApp.setActivationPolicy(.regular)` calls removed from VOCRAppDelegate, so the app never shows a Dock icon (verified at runtime: NSWorkspace reports `.accessory`, lsappinfo reports `type="UIElement"`). The split worker child processes were already `.prohibited` (no Dock). Net: repeated Finder OCR runs no longer pile up Dock icons. (Finder action still uses `open -n`; single-instance reuse was left out of scope since LSUIElement removes the Dock clutter on its own.)
- 2026-06-13: GUI split path verified headless on the 24-page dense PDF. `VOCR_HEADLESS=1 VOCR_CLI_PATH=... ./.build/release/VOCR dense.pdf` produced `dense_ocr.pdf` (24 pages, 49415 extracted chars) in ~6.5s vs ~26s single-process. Also verified the packaged `VOCR.app` (no VOCR_CLI_PATH) self-locates the bundled sibling CLI and runs the split path in ~6.6s. Combined TXT+PDF still runs the in-process path. (Updated 2026-09-13: combined TXT+PDF splits too since 2026-09-10, `436fddc`.)
- 2026-06-13: Cancel and pause E2E-verified on the split path via headless seams (`VOCR_HEADLESS=cancel` / `=pause`) on a 60-page PDF (full run ~13.4s). Cancel: 12 workers spawned, cancel fired at 1.5s, all workers terminated within ~0.7s, app exited at 2.3s, no orphan processes, no output written. Pause/resume: workers observed in `T` (stopped) state for the entire pause window (1.5s–4s) via `ps stat`, returned to `R` after resume, and the job completed with full 60-page output (wall ~15.7s = work + pause). The `cancel`/`pause` headless modes are gated test affordances alongside the existing `VOCR_HEADLESS` seam.

- 2026-09-09: Automated-test / speed / stability round. `swift build -c release` and
  `swift test` passed: 99 tests, 0 failures (was 91). The suite went from 0.243s to ~5.7s
  because the multi-process split path now has real process-spawning coverage instead of
  only unit tests: `Tests/AppleVisionOCRCoreTests/SplitProcessOCRRunnerProcessTests.swift`
  injects a fake worker via `executableURL` and asserts the FULL child argument vector per
  chunk (the b8856d6 `--page-breaks` regression class), progress parsing, worker-failure
  propagation with SIGKILL escalation, and cancel-while-paused with the worker verified in
  the `T` state. Added `.github/workflows/ci.yml` (macOS: `swift build -c release` +
  `swift test`; file created, remote run not yet confirmed),
  `scripts/verify-equivalence.sh` (single vs split: TXT `cmp`, page-break TXT `cmp`, PDF
  per-page extracted text, plus page-count and non-empty guards — all PASS on an 11-page
  fixture), `scripts/make-bench-fixture.py` (deterministic raster-only fixture generator;
  no benchmark fixture had ever been committed, so no earlier performance number was
  reproducible) and `scripts/bench.sh` (median wall time, summed process-tree peak RSS,
  per-worker finish spread).
  Shutdown hardening: `writeCombinedText` now refuses to replace an existing output and
  writes atomically (matching `mergePDFs`); worker termination escalates SIGTERM → 2s →
  SIGKILL; the error-path reader wait is bounded; split children get
  `APPLE_VISION_OCR_PARENT_PID` and self-exit when the parent dies. Known gaps left
  explicit: the success-path `readerGroup.wait()` is still unbounded, and a child SIGSTOPped
  when the parent dies still leaks (its watchdog is stopped too).
  Measured on a 120-page dense raster fixture (18 cores), TXT output:
  1 worker 343.75s / 1694 MB, 4 workers 103.78s / 2661 MB, 8 workers 65.27s / 3344 MB,
  12 workers 53.99s / 4243 MB. Three planned speed levers all measured null:
  worker-finish spread is only 11.5% of runtime (dynamic partitioning deferred);
  shrinking the render queue 32 → 4 with 120 pages in ONE process saves 9 MB (1682 → 1673 MB)
  and costs 6% wall time; limiting the existing-text scan to the selected page range makes
  no difference on scanned input (55.95/53.66s before vs 55.50/54.31s after) because such
  pages have no text layer to extract. The only measured win is worker count: interleaved
  12-vs-14 pairs gave 45.85/43.67, 45.55/43.75, 49.92/47.25 — 14 wins all three by 4-5%;
  16 is oversubscribed. Interleaved 13-vs-14 is a tie (39.91/42.64, 46.00/45.70,
  46.03/46.97), so changing `VOCRWindowController.swift:6` from
  `activeProcessorCount * 2 / 3` to `* 3 / 4` (13 on 18 cores) captures the win in one
  line. NOT applied — single machine, single document.
  Correction to an earlier note: `--page-parallelism` is NOT a no-op under split — child
  `pp=1` at 12 workers is 10% slower (54.42s) while saving 9% RSS (3853 MB).
- 2026-09-13 (v1.1.0): `swift test` passed: 105 tests, 0 failures. New
  `testFileListScrollsHorizontallyInsteadOfWrappingLongPaths` was mutation-checked (fails with
  `widthTracksTextView = true`). `scripts/make-release-package.sh` produced
  `VOCR-1.1.0-macos-arm64.zip` (no AppleDouble entries, no personal paths in text or binaries;
  both binaries declare `minos 13.0`, SDK 26.5). Installed from the unzipped, quarantine-marked
  package into a fake `HOME` with app dir `My Apps & Tools` and bin dir `bin dir`, twice: no
  build ran, quarantine removed, `codesign --verify --deep --strict` and `plutil -lint` OK,
  app and CLI report 1.1.0, and the workflow command (shell-quoted, XML-escaped) launched the
  app from the custom dir. Packaged CLI on a 5-page fixture with `--split-workers 2`:
  `--txt-only --page-range 2-3` → pages 2-3; `--page-range 3-4` PDF → 2 pages; TXT+PDF
  `--page-range 4-5` → pages 4-5 and a 2-page PDF; `--page-range 4-6` → exit 1
  `page range 4-6 exceeds page count 5`. Packaged app `VOCR_HEADLESS=1` on a 6-page fixture
  → 6-page `_ocr.pdf` in 7s. Not verified: a real macOS 13 machine, Intel, and the
  Gatekeeper dialog for a downloaded `Install.command`.

## Installed Artifact Verification

- `scripts/install-vocr-quick-action.sh` refreshed:
  - `~/Applications/VOCR.app`
  - `~/.local/bin/apple-vision-ocr`
  - `~/Library/Services/Apple Vision OCR.workflow`
- Installed CLI help shows `--page-parallelism 1-16`, defaults to 8, and includes `--render-scale 1.25|1.5|2.0`.
- Installed CLI hash matches `.build/release/apple-vision-ocr`.
- `codesign --verify --deep --strict ~/Applications/VOCR.app` passed.
- `plutil -lint` passed for the installed app plist and Quick Action plist/workflow.
- Earlier OCR smoke with page parallelism 4 on `.build/bench/sample-10.pdf` showed pages 1-4 entering render/OCR together, then pages 5-10 filling freed slots; runtime was `real 1.60`.
- Real Korean OCR smoke on `.build/bench/romans-speed-debug/page-1.pdf` with `--render-scale 1.5` produced readable Korean title/publisher text; runtime was `real 0.33`.
- Real Korean OCR smoke with `--render-scale 1.25` also avoided the prior unusable fast-mode path; runtime was `real 0.34` on the same one-page sample.

## 100-Page Korean Benchmark

Source:

- `local Korean theology PDF sample`
- First 100 pages split into `.build/bench/romans-100-20260517/romans-first-100.pdf`

Measured results:

- Apple Vision accurate, pp4, render 1.5, TXT: `real 77.27`
- Apple Vision accurate, pp8, render 1.5, TXT: `real 75.42`
- Apple Vision accurate, pp8, render 1.25, TXT: `real 76.35`
- Apple Vision accurate, pp8, render 2.0, TXT: `real 75.95`
- Apple Vision accurate, pp8, render 1.5, searchable PDF: `real 76.66`
- Apple Vision accurate, pp16, render 2.0, TXT: `real 76.78`
- Poppler 72dpi JPEG + Tesseract kor+eng pp8, TXT: about `25.42s` total
- Poppler 100dpi JPEG + Tesseract kor+eng pp8, TXT: about `26.55s` total
- Poppler 150dpi JPEG + Tesseract kor+eng pp8, TXT: about `33.00s` total
- Poppler 100dpi JPEG + Tesseract kor+eng pp8, searchable PDF: about `27.45s` total

Quality decision:

- Apple Vision accurate remains the quality-safe default.
- Tesseract is much faster but produced enough Korean/English mixed OCR errors on sampled pages that it should not replace Apple Vision as the normal output path.
- Render scale 1.5 did not materially beat 2.0 on this 100-page file, so keep quality render as the default and treat lower render scales as optional operator knobs.
- Page parallelism 8 is the best measured Apple Vision default. Page parallelism 16 is allowed for experiments but was slower than 8 on this benchmark.

## Next Validation Target

Searchable PDF split-workers are now implemented as a separate PDF-specific merge path (`ChunkedPDFOCRRunner`) with CoreGraphics `drawPDFPage` merge, exactly avoiding the rejected PDFKit chunk-rewrite approach that changed OCR output in testing. Remaining optional validation: confirm fidelity on rotated pages and on PDFs that already carry a selectable text layer (the rasterization branch), and measure on the full 398-page Korean reference. Note the merged PDF is modestly larger than single-process output (~20% on the test file) because per-chunk fonts/resources are not de-duplicated across the merge boundary.

If a draft-speed mode is desired, add it explicitly as a separate Tesseract backend with a clear quality warning rather than silently mixing it into the default Apple Vision path.

## OCR Model Candidate Retest

Follow-up benchmark doc:

- `docs/benchmarks/2026-05-17-ocr-model-candidates.md`

Additional findings:

- Tesseract was retested more fairly with 150/200/300dpi PNG, `kor+eng` / `eng+kor` / `script/Hangul+eng`, and `psm 3/4/6`.
- Tesseract quality does improve at 300dpi. On page 50, best tuned OCR-only similarity to the Apple Vision reference was `0.9241`, but 100-page 300dpi rendering timed out at 240s before OCR started. That removes it as a speed replacement.
- RapidOCR + Korean PP-OCRv5 recognition was installed in a repo-local venv and benchmarked:
  - 20 pages OCR-only: `14.32s`, mean similarity `0.8854`.
  - 100 pages OCR-only on existing 150dpi images: `88.19s`, mean similarity `0.8591`, worst pages down to `0.4211`.
- PaddleOCR + Korean PP-OCRv5 was installed in the same repo-local venv and sampled on page 50:
  - server detector + Korean recognizer: `19.98s` predict, similarity `0.9418`.
  - mobile detector + Korean recognizer: `8.73s` predict, similarity `0.8839`.
- GLM-OCR was retested locally through downloaded MLX model artifacts, without custom conversion:
  - repo-local env: `.build/bench/glm-mlx-20260517/.venv`
  - downloaded models: `GLM-OCR-bf16`, `GLM-OCR-8bit`, `GLM-OCR-4bit`, `EZCon-GLM-OCR-mlx`
  - 8bit, 150dpi JPEG, pages 10/50/62: `62.45s` total, `20.82s/page`, mean similarity `0.8198`
  - 8bit, 100dpi JPEG, pages 10/50/62: `35.56s` total, `11.85s/page`, mean similarity `0.8186`
  - BF16, 150dpi page 50: `26.35s`, similarity `0.8755`
  - 8bit, 150dpi page 50: `21.91s`, similarity `0.8761`
  - 4bit, 150dpi page 50: failed with a UTF-8 decode error during generation
  - Output still contains unacceptable Korean substitutions such as `언약` -> `연약`, `로마서` -> `모마서`, and `택하셨다` -> `탑하였다`.
- Isolated Ollama `glm-ocr:q8_0` pull was attempted with `OLLAMA_MODELS` inside `.build/bench/glm-mlx-20260517/ollama-models`, but the installed Ollama `0.15.4` rejected the manifest because the model requires a newer Ollama version. The temporary Ollama server was stopped after the check.

Decision remains unchanged: Apple Vision accurate stays the normal quality-safe backend. Tesseract can be considered only as an explicit rough-draft backend; Paddle/RapidOCR and local GLM-OCR MLX should not be added as default dependencies yet.
