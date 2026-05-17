# Current Status

Updated: 2026-05-18

## Current Objective

The product goal is not to force Apple Vision `fast` mode onto Korean OCR.
Apple Vision `fast` does not support `ko-KR` on the tested macOS version and produces unusable text.

The current goal is:

1. Keep Korean/default OCR on Apple Vision `accurate`.
2. Prevent unsupported fast-mode Korean output.
3. Improve Korean OCR throughput through safe knobs:
   - page-level parallelism;
   - lower PDF render scale for optional speed-balanced runs.
4. Benchmark those safe knobs before deciding whether an external OCR engine is justified.

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

## Fresh Verification

- 2026-05-18: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test` passed: 75 tests, 0 failures.
- 2026-05-18: `env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release` passed after rerunning outside the Codex sandbox because SwiftPM manifest sandboxing failed with `sandbox-exec: sandbox_apply: Operation not permitted`.

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
