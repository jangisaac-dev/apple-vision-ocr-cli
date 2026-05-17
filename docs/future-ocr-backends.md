# Future OCR Backend Notes

Apple Vision accurate mode is the current quality-safe backend for Korean/default OCR. Do not replace it unless a future benchmark proves both better speed and acceptable Korean text quality on the same long-document workload.

## Current Default

- Backend: Apple Vision `VNRecognizeTextRequest`.
- Recognition level: `accurate` for default `ko,en`.
- Page parallelism: default `8`, configurable `1-16`.
- Render scale: `2.0` quality default, with `1.5` and `1.25` as operator speed/size knobs.
- Apple Vision `fast` is English-only in this app because the tested macOS Vision language set does not support Korean fast recognition.

## Candidate Summary

| Candidate | Current status | Reason |
| --- | --- | --- |
| Tesseract 150dpi | Possible rough-draft mode only | Fast, but sampled Korean theology pages had too many substitutions and Latin noise. |
| Tesseract 300dpi tuned | Not a speed replacement | Page 50 quality improved, but 100-page rendering timed out before OCR started. |
| RapidOCR Korean PP-OCRv5 | Reject as default | 100-page OCR-only run was slower than Apple Vision and lower quality before PDF reconstruction. |
| PaddleOCR Korean PP-OCRv5 | Reject as default | Page-level quality was mixed and per-page runtime was too high. |
| GLM-OCR MLX BF16 / 8bit | Reject as default | Local MLX inference works, but it was much slower than Apple Vision and misread core Korean terms. |
| GLM-OCR MLX 4bit | Reject | Generation failed with a UTF-8 decode error in the tested setup. |
| Ollama GLM-OCR | Not benchmarked | Installed Ollama rejected the model manifest because the model requires a newer Ollama version. |

## GLM-OCR Local MLX Record

The GLM-OCR local test used downloaded MLX model artifacts only, with no custom conversion:

- `mlx-community/GLM-OCR-bf16`
- `mlx-community/GLM-OCR-8bit`
- `mlx-community/GLM-OCR-4bit`
- `EZCon/GLM-OCR-mlx`

The benchmark environment and generated artifacts are intentionally under `.build/bench/glm-mlx-20260517/`, which is ignored by Git because it contains downloaded models, virtual environments, and benchmark outputs.

Measured local MLX result highlights:

- 8bit, 150dpi JPEG, pages 10/50/62: `62.45s` total, `20.82s/page`, mean similarity `0.8198`.
- 8bit, 100dpi JPEG, pages 10/50/62: `35.56s` total, `11.85s/page`, mean similarity `0.8186`.
- BF16, 150dpi page 50: `26.35s`, similarity `0.8755`.
- 8bit, 150dpi page 50: `21.91s`, similarity `0.8761`.
- 4bit, 150dpi page 50: failed with a UTF-8 decode error during generation.

The page 50 GLM-OCR outputs repeatedly misread important Korean terms, including `언약`, `로마서`, and `택하셨다`. This fails the quality requirement even before considering the much slower per-page runtime.

## Extension Rule

Any future backend must be added as an explicit backend or mode with clear user-facing quality expectations. Do not silently route Korean/default OCR away from Apple Vision accurate mode.

Before promoting a backend:

1. Benchmark it on the same 100-page Korean sample class used in the existing benchmark docs.
2. Compare against the Apple Vision reference output.
3. Inspect sampled Korean body text manually for theological term substitutions, footnote degradation, and line loss.
4. Include full render plus OCR plus output-writing time, not OCR-only time.
5. Keep downloaded models, caches, virtual environments, and generated benchmark outputs out of Git.

Detailed evidence remains in `docs/benchmarks/2026-05-17-ocr-model-candidates.md`.
