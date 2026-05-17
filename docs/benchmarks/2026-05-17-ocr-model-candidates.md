# OCR Model Candidate Benchmark

Date: 2026-05-17
Source PDF: `local Korean theology PDF sample`
Benchmark subset: first 100 pages, split at `.build/bench/romans-100-20260517/romans-first-100.pdf`

## Goal

Find a faster OCR path without giving up Korean theology-book text quality. Speed-only output is not acceptable.

## Candidate Sources Checked

- Tesseract 5.5.2 local install. Tesseract's own quality guide recommends at least 300dpi input for best results: https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html
- PaddleOCR PP-OCRv5 documentation: Korean is a supported language abbreviation (`korean`), and `korean_PP-OCRv5_mobile_rec` supports Korean plus English: https://www.paddleocr.ai/latest/en/version3.x/algorithm/PP-OCRv5/PP-OCRv5_multi_languages.html
- RapidOCR 3.8.1 documentation/source package: ONNXRuntime PaddleOCR-derived engine with downloadable PP-OCRv5 Korean recognition model: https://github.com/RapidAI/RapidOCR
- GLM-OCR official project: 0.9B multimodal OCR model with SDK/self-host options, including an Apple Silicon `mlx-vlm` guide: https://github.com/zai-org/GLM-OCR and https://github.com/zai-org/GLM-OCR/blob/main/examples/mlx-deploy/README.md
- GLM-OCR MLX downloads checked without local conversion: `mlx-community/GLM-OCR-bf16`, `mlx-community/GLM-OCR-8bit`, `mlx-community/GLM-OCR-4bit`, and `EZCon/GLM-OCR-mlx`: https://huggingface.co/mlx-community/GLM-OCR-bf16, https://huggingface.co/mlx-community/GLM-OCR-8bit, https://huggingface.co/mlx-community/GLM-OCR-4bit
- Ollama also publishes `glm-ocr`, `glm-ocr:q8_0`, and `glm-ocr:bf16`, but the installed local Ollama `0.15.4` rejected `glm-ocr:q8_0` with a "requires a newer version of Ollama" manifest error: https://ollama.com/library/glm-ocr
- EasyOCR and Surya were screened as installable Python candidates, but not promoted to long-run benchmark in this pass because both add heavy Python/PyTorch runtime surface and are less directly aligned with searchable-PDF local packaging than Tesseract/Paddle-derived engines: https://github.com/JaidedAI/EasyOCR and https://pypi.org/project/surya-ocr/

## Results

| Engine / mode | Scope | Time | Quality result | Decision |
| --- | ---: | ---: | --- | --- |
| Apple Vision accurate, pp8, render 2.0 | 100 pages TXT | 75.95s | best sampled Korean text among local candidates | keep as quality-safe default |
| Tesseract 150dpi JPEG, `kor+eng`, pp8 | 100 pages TXT | 33.00s | faster, but real Korean body pages still contain substitutions like `죄를` -> `AS` / mixed Latin noise | draft only |
| Tesseract tuned 300dpi PNG, `kor+eng`, `psm 3` | page 50 sample | 2.49s OCR-only | much better than 150dpi; still has errors in theological body/footnote text | not enough quality win |
| Tesseract tuned 300dpi PNG | 100-page render | timed out at 240s during render, before OCR | quality input cost alone exceeds Apple Vision total | reject as speed path |
| RapidOCR ONNXRuntime + Korean PP-OCRv5 rec | 20 pages OCR-only | 14.32s | mean similarity to Apple reference 0.8854; worst page 0.7371 | too lossy |
| RapidOCR ONNXRuntime + Korean PP-OCRv5 rec | 100 pages OCR-only on existing 150dpi images | 88.19s | mean similarity 0.8591; worst pages down to 0.4211 | slower than Apple before render, lower quality |
| PaddleOCR PP-OCRv5 server detector + Korean rec | page 50 sample | 19.98s predict | good line coverage, similarity 0.9418, but spacing/typos remain | too slow |
| PaddleOCR PP-OCRv5 mobile detector + Korean rec | page 50 sample | 8.73s predict | lower line coverage, similarity 0.8839 | too slow and lower quality |
| GLM-OCR remote console | health check | timeout at 8s | remote candidate not reachable during this pass | include as future GPU/remote candidate, not local default |
| Local GLM/VARCO workspace | runtime check | MPS unavailable, CPU-only | local 100-page run would not be comparable | do not run locally for speed decision |
| GLM-OCR MLX BF16, 150dpi JPEG | page 50 sample | 26.35s | similarity 0.8755; substitutions like `택하셨다` -> `탑하였다`, `언약` -> `연약`, `로마서` -> `모마서` | slower than Apple per page and lower quality |
| GLM-OCR MLX 8bit, 150dpi JPEG | page 50 sample | 21.91s | similarity 0.8761; same Korean theological term substitutions as BF16 | reject as default |
| GLM-OCR MLX 8bit, 150dpi JPEG | pages 10, 50, 62 | 62.45s total, 20.82s/page | mean similarity 0.8198 | not viable for 100 pages |
| GLM-OCR MLX 8bit, 100dpi JPEG | pages 10, 50, 62 | 35.56s total, 11.85s/page | mean similarity 0.8186; lower prompt-token cost, still too many Korean errors | too lossy |
| GLM-OCR MLX 4bit, 150dpi JPEG | page 50 sample | 14.69s before failure | generation crashed with UTF-8 decode error | reject |
| Ollama `glm-ocr:q8_0` | isolated local model pull | blocked | installed Ollama `0.15.4` requires upgrade for this model manifest | not benchmarked |

## Tesseract Retest Notes

The user was right to challenge the first Tesseract result. The earlier 72/100/150dpi JPEG tests were not the best-quality Tesseract configuration.

Retest details:

- Tested pages 10, 50, 62.
- Tested 150/200/300dpi PNG.
- Tested `kor+eng`, `eng+kor`, and `script/Hangul+eng`.
- Tested `psm 3`, `psm 4`, `psm 6`, `--oem 1`.

Best page 50 setting:

- `300dpi`, `kor+eng`, `psm 3`
- Similarity to Apple Vision reference: `0.9241`
- OCR-only time: `2.4864s`

This is meaningfully better than the prior 150dpi output, but 300dpi PDF rendering for 100 pages timed out at 240 seconds before OCR even started. That makes tuned Tesseract a poor speed replacement for this app.

## Paddle / RapidOCR Notes

PaddleOCR and RapidOCR both made Korean PP-OCRv5 usable locally after installing into a repo-local venv:

- `.build/bench/ocr-candidates-20260517/.venv`
- `rapidocr`, `onnxruntime`, `paddleocr`, `paddlepaddle`

RapidOCR was fast on OCR-only inference, but missed or degraded enough Korean lines that it failed the quality bar. PaddleOCR server detection gave better page 50 line coverage, but one page took about 20 seconds. At 100 pages that is not a viable speed path.

## GLM-OCR Notes

GLM-OCR is included in the candidate set, and local Apple Silicon MLX inference was tested from downloaded model artifacts only. It is not a local drop-in replacement for this CLI right now.

- Official GLM-OCR is a VLM-style document OCR stack. It is promising for complex document understanding, not a simple native macOS searchable-PDF dependency.
- The existing sibling project `a sibling GLM-OCR workspace` uses a remote console pattern and defaults to `NCSOFT/VARCO-VISION-2.0-1.7B-OCR`.
- Remote health check to `<private GLM-OCR remote>/health` timed out on 2026-05-17.
- Local torch check in that workspace reported `mps False`, so local Mac execution would be CPU-only and not meaningful for a speed benchmark.
- Separate local MLX benchmark env: `.build/bench/glm-mlx-20260517/.venv`.
- Required packages for the tested MLX path: `mlx`, `mlx-vlm`, `huggingface_hub`, `pillow`, `requests`, plus `torch` and `torchvision` because GLM-OCR image processing depends on `AutoImageProcessor`. Without `torch`/`torchvision`, the image processor did not load correctly and outputs were empty or single-character garbage.
- Downloaded model directories:
  - `.build/bench/glm-mlx-20260517/models/GLM-OCR-bf16`
  - `.build/bench/glm-mlx-20260517/models/GLM-OCR-8bit`
  - `.build/bench/glm-mlx-20260517/models/GLM-OCR-4bit`
  - `.build/bench/glm-mlx-20260517/models/EZCon-GLM-OCR-mlx`
- Benchmark script: `.build/bench/glm-mlx-20260517/run_glm_mlx.py`. It loads each model once, applies the GLM-OCR image chat template, runs selected page images, saves page text, and compares normalized text to the Apple Vision reference.
- 8bit is the best local MLX speed/quality point tested, but it is still too slow for the 100-page target. At 100dpi it extrapolates to roughly 19.8 minutes for 100 pages before PDF reconstruction overhead; at 150dpi it extrapolates to roughly 34.7 minutes. Apple Vision accurate finished the same 100-page TXT benchmark in about 76 seconds.
- Quality is below the requirement even when similarity looks moderate. On page 50, GLM-OCR repeatedly misread core terms and common words: `택하셨다` became `탑하였다`, `언약` became `연약`, `헌법` became `한법`, `로마서` became `모마서`, and `거꾸로 읽는 로마서` became `거꾸로 외는 모마서`.

## Recommendation

Do not replace Apple Vision for the normal Korean/default path.

Add a separate optional draft backend only if the product needs “quick rough text”:

- `Tesseract 150dpi` for draft-speed text, with a visible quality warning.
- Keep Apple Vision accurate as the default for searchable PDF / reliable Korean output.
- Keep GLM-OCR as a separate remote/GPU experiment, not as a local CLI dependency. The local MLX path works, but current downloaded MLX variants are slower and lower quality than Apple Vision on this Korean theology PDF.

## Evidence Artifacts

- Tesseract tuning: `.build/bench/ocr-candidates-20260517/tesseract-tuned/top.json`
- Tesseract 300dpi timeout script: `.build/bench/ocr-candidates-20260517/run_tesseract_100.py`
- RapidOCR 20-page result: `.build/bench/ocr-candidates-20260517/rapidocr-150jpg-20/summary.json`
- RapidOCR 100-page result: `.build/bench/ocr-candidates-20260517/rapidocr-150jpg-100/summary.json`
- PaddleOCR page 50 result: `.build/bench/ocr-candidates-20260517/paddle-page50/summary.json`
- GLM-OCR MLX script: `.build/bench/glm-mlx-20260517/run_glm_mlx.py`
- GLM-OCR MLX 150dpi 8bit 3-page result: `.build/bench/glm-mlx-20260517/results-150jpg-pages-10-50-62/summary.json`
- GLM-OCR MLX 100dpi 8bit 3-page result: `.build/bench/glm-mlx-20260517/results-100jpg-pages-10-50-62/summary.json`
- GLM-OCR MLX page 50 model comparison: `.build/bench/glm-mlx-20260517/results-150jpg-smoke/`
