# 레이아웃 구분 Markdown 출력 설계

작성: 2026-10-27
검토: 외부 advisor(codex), 내장 advisor, agy Argon 기획 리뷰 반영
상태: 구현됨 (feature/layout-markdown, 2026-10-27). 검증 결과는 CURRENT_STATUS.md 2026-10-27 항목
구현 중 리뷰·실측으로 바뀐 규칙(머리말 후보는 줄 끝 또는 줄 머리 숫자만 쪽번호로 판정, 표시 없는 잡음 각주만 제거, 번호가 이어질 때 같은 쪽 각주 조각을 앞 각주에 이어 붙임, 여러 단계 번호 한 줄은 소제목)은 커밋 b7e1825, 84a0531, 7e91fd3 참고.

## 목표

OCR 결과에서 제목·소제목·본문·각주·쪽번호가 섞이지 않게 Markdown 파일로 낸다.
기존 장점(멀티프로세스 split 속도, CLI, GUI, 기존 TXT·PDF 출력)은 그대로 둔다.

## 사용자 결정 (2026-10-26~27)

- 판별 방식: 레이아웃 모델(PP-DocLayoutV3 CoreML). 규칙 기반 방식은 쓰지 않는다.
- 최소 macOS: 26. macOS 13~25 사용자는 GitHub의 v1.3.1 릴리스를 그대로 쓴다.
- 각주: Markdown 각주 문법(`[^4]`)으로, 정의는 문서 끝에 모은다.
- 글이 비어 있는 영역은 잘라서 다시 OCR한다(이번 범위에 포함).

## 실험 근거 (2026-10-27, 학술지 3종 11쪽, macOS 27)

시험 파일: `98_논문/2026-최성훈-동물윤리의 역사와 현대적 과제.pdf` 외
`2022-권호-…설교인가？.pdf`, `2023-최성훈-종교인 과세의 문제점 및 개선방안.pdf`.

- 각주가 표시 방식(`4)`, `1 `, `*`)과 상관없이 하나씩 `footnote`로 잡혔다(점수 0.78~0.95).
- 머리말(`header`), 쪽번호(`number`), 소제목(`paragraph_title`), 논문 제목(`doc_title`), 초록(`abstract`)이 구분됐다.
- KCI 로고: 한 학술지에서는 `footer`로 잡혔고, 나머지 둘에서는 어느 영역에도 들어가지 않았다.
- 짝수 쪽 머리말 1개(KCI 논문 2쪽, `710• 신학과 실천(Theology and Praxis)`)를 놓쳤다. 그 쪽은 `number`도 못 잡았다.
- 5쪽 각주 9번은 KCI 로고와 겹쳐 쪽 전체 OCR에서 통째로 빠진다(현재 TXT 출력도 같다). 그 영역만 잘라 다시 OCR하면 `9) Lymn Wite, Jr, …`로 되살아난다(오자 있음).
- `number` 영역만 잘라 OCR하면 `• 713`이 나온다.
- 쪽 여백의 OCR 줄 높이(쪽 줄 높이 중앙값 대비): KCI 로고 줄 2.32~2.82배, 각주·본문·머리말 줄 0.82~1.29배. 로고 조각 하나(`O`)는 1.18배였다.
- 머리말과 본문 첫 줄의 세로 위치(위가 0): KCI는 머리말 0.120, 본문 0.153~0.16. 종교인 과세 논문은 머리말 0.091, **본문 첫 줄 0.125**. 위치만으로는 둘을 가를 수 없다.
- 모델 추론 호출 자체는 쪽당 약 0.04초였다. 전처리, 재OCR, 표 처리, 여러 프로세스 동시 실행 때의 경합과 메모리는 재지 않았다.
  첫 실행에서 약 11초의 시스템 컴파일이 있었고, 다음 프로세스부터는 모델 로드가 0.1초 안이었다. 이 캐시가 언제까지 유지되는지는 모른다.
- CI 러너: `macos-latest`가 이미 `macos-26-arm64` 이미지다(2026-09-13 실행 34767680571).
- `xcrun coremlcompiler compile … --platform macos --deployment-target 26.0`이 이 모델로 정상 동작한다.

**관문 시험 (2026-10-27, `order_logits` 계산 포함):**
- 2단 편집은 `98_논문` 표본 148편(3·4쪽 또는 2~7쪽)에서 잡지 기사 1편(`2001-Long Thomas G-Between opposing forces…`, 3단)뿐이었다.
  그 기사 4쪽은 읽기 순서가 맞았고, 3쪽은 두 단에 걸친 그림 때문에 가운데 단 위쪽 다음에 오른쪽 단 위쪽을 읽어 틀렸다(글 이음으로 확인).
- 표: `2007-안선덕` 6쪽 표 2개, `2008-반신환` 3쪽 표 1개 모두 칸 구조가 나왔고, 병합 셀은 `rowRange`·`columnRange`로 정확히 표시됐다.
- KCI 5쪽: 각주 4~8이 각주로 잡히고 9가 재OCR로 되살아났다. 재OCR 결과 앞에 잘린 로고 조각(`LOW 10R AL`, 높이 0.36배)이 붙었고 각주 줄은 1.08배였다.
- `2007-안선덕` 6쪽 맨 아래 각주 `11) 본문에서…`가 `footnote`가 아니라 `text`(0.54)로 분류됐다.

macOS 26에서는 돌려 보지 않았다.

Apple `RecognizeDocumentsRequest`만으로는 각주·쪽번호·머리말을 구분하지 못했고 `title`도 틀렸다(같은 세션 실측). 이 API는 표에만 쓴다.

## 구조

쪽 처리와 Markdown 생성을 둘로 나눈다.

1. **쪽 분석** (쪽마다, 병렬): `SearchablePDFPipeline`의 기존 쪽 소비자에서 OCR 직후, 같은 렌더 이미지로 레이아웃 → 줄 배정 → 재OCR → 표를 처리해 쪽 구조 데이터 `MarkdownPage`를 만든다.
   렌더링, 렌더 큐, 쪽 병렬, 진행률, 취소·일시정지는 기존 것을 그대로 쓴다.
   Markdown 모드는 PDF를 쓰지 않으므로 기존 글자층 검사(`pagesWithExistingTextIfNeeded`)를 타지 않고 모든 쪽을 OCR한다.
2. **문서 조립** (한 번): 모든 쪽의 `MarkdownPage`를 순서대로 받아 머리말 확인, 쪽번호 보충, 각주 이름표·참조·이어짐을 정하고 Markdown 문자열을 만든다.

단일 프로세스와 split 모두 같은 문서 조립 함수를 쓴다. 그래서 두 결과가 같다.

```
MarkdownPage (Codable)
  pdfPage: Int                 // 1부터
  printedPage: Int?            // number 영역에서 읽은 숫자
  topCandidates: [String]      // 머리말일 수 있는 위쪽 미배정 줄 (조립 때 판정)
  blocks: [Block]              // 읽기 순서
    kind: title | heading | paragraph | table
    text: String               // table이면 이미 만든 Markdown 표
  footnotes: [Footnote]        // 쪽 안 위→아래 순서
    marker: String?            // "4", "*", 또는 표시 없음(nil)
    text: String               // 표시를 뺀 본문, 줄바꿈 유지
```

## 동작

### 입력과 출력

- 새 출력 모드 `markdown`. Markdown만 단독으로 낸다(같은 실행에서 PDF·TXT와 함께 내지 않는다).
- CLI (`--txt-only`/`--txt-output` 규약을 따른다)
  - `--md-only`: 출력 `입력이름.md`.
  - `--md-output PATH`: 경로 지정. 단독으로 써도 Markdown만 낸다. `--md-only`와 함께 써도 된다.
  - 확장자는 `.md`여야 한다(`validateFileSystem`에서 TXT와 같은 방식으로 검사).
  - `--output`, `--txt`, `--txt-only`, `--txt-output`, `--page-breaks`와 함께 쓰면 사용 오류(exit 1).
  - `--split-workers`, `--page-range`, `--lang`, `--recognition-level`, `--render-scale`, `--no-language-correction`, `--dry-run`은 그대로 쓸 수 있다. 인식 수준·언어·교정 옵션은 쪽 OCR, 재OCR, 표 인식에 똑같이 쓴다.
  - 성공하면 stdout에 `.md` 경로 한 줄을 낸다.
- split 자식 전용 내부 옵션 `--md-pages-output PATH`(`.json`): Markdown 대신 `[MarkdownPage]` JSON을 쓴다. 다른 출력 옵션이나 `--split-workers`와 함께 쓰면 사용 오류. `--help`에는 넣지 않는다.
- 모델을 못 찾거나 불러오지 못하면 OCR 시작 전에 exit 4(`visionFailure`)로 끝낸다. 메시지에 `APPLE_VISION_OCR_LAYOUT_MODEL`과 `scripts/fetch-layout-model.sh`를 적는다. `--dry-run`도 같은 검사를 한다.
- 단일 프로세스 출력은 임시 파일에 쓴 뒤 옮기고, 이미 있는 파일은 덮어쓰지 않는다(`SplitProcessOCRRunner.writeCombinedText`와 같은 방식. `TextOutputWriter`의 `atomically: true`는 덮어쓰므로 쓰지 않는다).
- 진행률은 쪽 하나의 레이아웃·재OCR·표까지 끝난 뒤에 `Completed page `를 낸다(split 부모가 이 줄을 센다).
- 취소·일시정지는 지금처럼 쪽 사이에서 확인하고, 재OCR과 표 인식 직전에 한 번 더 확인한다.
- 기존 TXT 출력은 바이트 단위로, PDF 출력은 쪽별 추출 텍스트가 바뀌지 않는다(PDF는 생성 시각 메타데이터 때문에 실행마다 바이트가 다르다). 레이아웃 모델은 Markdown 모드에서만 불러온다.

### 연결 지점

- Core: `OCRJobOutputMode`(Markdown 플래그, PDF·TXT와 배타), `OCRJobOutputSelection`, `OCRJobOptions`(Markdown 출력 URL), `OutputPathResolver`·`UniqueOutputPathResolver`(`.md`, 배치에서 `입력(1).md`), `CLIOptions`, `SearchablePDFPipeline`.
- split: `SplitProcessOCRRunner.Output`에 `.markdown(URL)`을 더한다. 새 러너 타입은 만들지 않는다. 자식 환경변수는 지금처럼 부모 환경을 물려받으므로 `APPLE_VISION_OCR_LAYOUT_MODEL`도 전달된다.
- CLI: `CommandRunner`의 split 분기에서 Markdown을 텍스트 폴백(`ChunkedTextOCRRunner`)보다 먼저 검사한다. 실행 파일 경로는 `resolvingSymlinksInPath()`로 푼다(`defaultExecutableURL`의 `standardizedFileURL`은 심볼릭 링크를 따라가지 않는다).
- GUI: `VOCRWindowController`(체크박스, `outputPreviewText`, `noteOutput`), `OCRJobController`(`VOCRJobOutput`, `prepareJobs`, split/단일 분기), `VOCRStrings`(영어·한국어), `VOCRAppDelegate.startHeadless`(헤드리스 검증 시드).

### GUI

- 출력 체크박스 묶음에 "Markdown (레이아웃 구분)" / "Markdown (layout)" 체크박스를 하나 더한다.
- Markdown을 켜면 텍스트·쪽 구분·PDF 체크박스를 끄고 비활성화한다. Markdown을 끄면 다시 활성화한다(PDF 기본값은 켬으로 되돌린다).
- 창(680×580, 크기 고정)에 한 줄이 들어가지 않으면 창 높이를 그 줄만큼 늘린다.
- 단일 프로세스 폴백에서는 앱 프로세스가 모델을 불러온다. 경로 규칙은 CLI와 같다(앱 실행 파일 기준 `../Resources/`).

### 쪽 분석

1. 지금처럼 쪽을 그리고 accurate OCR로 줄 단위 글자와 상자를 얻는다.
   Vision 상자(왼쪽 아래 원점)는 위쪽 원점으로 바꿔 쓴다: `y = 1 − maxY`.
2. 모델 입력: `pixel_values` `[1, 3, 800, 800]` Float16, RGB 순서, 채널 우선(NCHW).
   같은 쪽 이미지를 800×800으로 늘리고(비율 유지 안 함) 각 값을 255로 나눈다. 평균·표준편차 보정은 없다.
3. 모델 출력: `logits` `[1, 300, 25]`, `pred_boxes` `[1, 300, 4]`, `order_logits` `[1, 300, 300]`(모두 Float16, sigmoid 전 값). `out_masks`는 쓰지 않는다.
   질의마다 클래스 25개 중 logit 최댓값을 고르고, 그 sigmoid 점수가 0.4 이상인 질의만 영역으로 남긴다.
   상자는 `pred_boxes`(cx, cy, w, h, 0~1, 위가 원점)를 그대로 쓴다.
4. 읽기 순서: transformers `PPDocLayoutV3ImageProcessor._get_order_seqs`와 같게, **300개 질의 전체**로 먼저 계산한 뒤 남은 영역만 그 순서로 정렬한다.
   `S = σ(order_logits)`, `votes[j] = Σ_{i<j} S[i,j] + Σ_{i>j} (1 − S[j,i])`, `votes` 오름차순. 값이 같으면 질의 번호가 작은 쪽이 먼저(안정 정렬).
5. 줄 배정: 영역을 상하좌우 각각 가로 0.005, 세로 0.004씩 넓혀서, 줄 상자 중심이 들어가는 영역을 찾는다.
   - 여러 영역에 들면 블록을 만드는 영역(아래 표에서 "삭제"와 `number`가 아닌 것)을 우선하고, 그 안에서 면적이 가장 작은 영역에 넣는다.
     로고·인장 상자가 각주보다 작아서 각주 줄을 빼앗는 것을 막기 위해서다.
   - 영역 안의 줄 순서는 Vision 결과 순서를 그대로 쓴다(지금의 TXT와 같음).
6. 어느 영역에도 들어가지 않은 줄은 기본적으로 남긴다.
   - 가로로 겹치는 블록 영역 중 그 줄 바로 위에 있는 영역 뒤에 별도 문단으로 둔다. 그런 영역이 없으면 쪽 맨 앞에 둔다.
   - 같은 자리에 붙는 미배정 줄이 여러 개면 한 문단으로 묶는다.
   - **위쪽 머리말 후보:** 모든 블록 영역보다 위에 있고 줄 중심이 쪽의 위 14% 안이면 지우지 않고 `topCandidates`에 넣는다. 조립 단계에서 판정한다.
   - **아래쪽 로고 삭제:** 모든 블록 영역보다 아래에 있고, 줄 중심이 아래 14% 안이며, 줄 높이가 그 쪽 줄 높이 중앙값의 1.5배 이상이면 지운다. 실측 로고는 2.32배 이상이었고 각주 줄은 1.29배 이하였다.
7. 영역이 하나도 없는 쪽은 모든 줄을 한 문단으로 낸다(지금의 TXT와 같은 내용).
8. 빈 영역 재OCR: 블록을 만드는 영역이나 각주 영역인데, 넓히지 않은 상자 안에 **OCR 줄 중심이 하나도 없으면** 다시 OCR한다.
   상하좌우로 0.01만큼 여유를 두고(이미지 경계에서 자름) 잘라 같은 옵션의 OCR을 한 번 더 돌린다.
   다른 상자와 겹친 중복 상자는 그 안에 이미 다른 줄의 중심이 있으므로 다시 돌지 않는다(KCI 22쪽에서 실제로 겹친 `text` 상자가 나왔다).
   재OCR로 얻은 줄 중 높이가 쪽 줄 높이 중앙값의 0.6배 미만인 줄은 버린다(자른 경계에 걸린 로고 글자 조각).
   `number`와 `table`은 이 단계를 타지 않고 각자의 단계만 탄다.
9. 쪽번호: `number` 영역이 있으면 잘라 OCR하고, 첫 번째 숫자열(1~5자리)을 `printedPage`로 쓴다.
10. 각주 영역은 첫머리 표시를 읽어 `marker`와 `text`로 나눈다.
    - `4)`, `(6)`처럼 괄호가 붙은 1~3자리 숫자, 또는 뒤에 공백이 오는 1~3자리 숫자(`1 `)는 그 숫자.
      4자리 이상(`1998, pp.`)은 표시로 보지 않는다.
    - `*`, `†`, `‡`는 그 기호. 표시가 없으면 nil.
11. 아래쪽 `text`를 각주로 바로잡기: 쪽 아래에서 위로 영역을 훑는다(삭제 영역과 `number`는 건너뛴다).
    `footnote`면 계속, 중심이 쪽 아래 절반에 있는 `text`이고 첫 줄이 괄호형 표시(`4)`, `(6)`, 1~3자리)로 시작하면 `footnote`로 바꾸고 계속, 그 밖의 영역을 만나면 멈춘다.
    바뀐 영역 위에 블록 영역이 하나도 남지 않으면 바꾸지 않는다(쪽 전체가 번호 목록인 경우).

### 분류별 블록

| 클래스 | 블록 |
|---|---|
| `doc_title` | title (`# 제목`) |
| `paragraph_title` | heading (`## 소제목`, 단계 구분 없음) |
| `footnote` | 각주 |
| `table` | table (아래) |
| `header`, `footer`, `header_image`, `footer_image`, `seal` | 삭제 |
| `number` | `printedPage`에만 씀 |
| 나머지 전부 (`text`, `abstract`, `content`, `reference_content`, `figure_title`, `vision_footnote`, `image` 안의 글 등) | paragraph |

- title·heading 안의 줄바꿈은 공백으로 잇는다(두 줄짜리 제목이 한 제목으로 남게).
- 문단 안의 줄바꿈은 OCR 결과 그대로 둔다. 한글 줄 끝을 붙일지 띄울지 알 수 없어서다.
- 문단 줄이 `#`으로 시작하면 `\#`로 바꾼다(본문이 제목으로 보이지 않게). 다른 Markdown 기호는 건드리지 않는다.
- `vision_footnote`는 이름으로 보아 그림·표 아래 주석으로 가정하고 제자리 문단으로 둔다. PaddleOCR 문서와 모델 카드에 정의가 없어 확인하지 못했다. 실측 11쪽에서는 나오지 않았다.

### 표

- `table` 영역을 잘라 `RecognizeDocumentsRequest`(macOS 26)를 돌린다. `textRecognitionOptions`의 `recognitionLanguages`, `useLanguageCorrection`에 실행 옵션을 그대로 넣는다.
- 이 API는 `async`다. 쪽 소비자는 GCD 스레드이므로, 표 하나마다 `Task`를 띄우고 세마포어로 기다린다. Swift 동시성 협력 스레드에서 기다리는 것이 아니므로 협력 스레드 풀을 막지 않는다.
- `document.tables`의 모든 표를 차례로 Markdown 표로 바꾼다. 첫 행 뒤에 `| --- |` 구분 줄, 칸 안의 `|`는 `\|`, 칸 안 줄바꿈은 공백.
- 병합 셀(`rowRange`·`columnRange`가 2칸 이상)은 내용을 왼쪽 위 칸에만 넣고 나머지 칸은 비운다.
- 표 구조가 안 나오면 그 영역의 OCR 줄을 문단으로 낸다.

### 문서 조립

- **머리말 후보 판정:** 쪽 p의 기대 쪽번호는 p 자신의 `printedPage`, `printedPage(p−1) + 1`, `printedPage(p+1) − 1` 중 알려진 것들이다.
  `topCandidates`의 줄이 기대 쪽번호와 같은 독립된 숫자열을 가지면 머리말로 보고 지운다. 그 쪽에 `printedPage`가 없으면 그 숫자로 채운다.
  나머지 후보는 쪽 맨 앞 문단으로 남긴다. 예: KCI 2쪽의 `710• 신학과 실천…`은 3쪽의 711에서 기대값 710을 얻어 지워지고 `[p. 710]`이 된다.
- 쪽마다 맨 앞에 쪽 표시 한 줄: `printedPage`가 있으면 `[p. 713]`, 없으면 `[PDF p. 5]`. 블록 사이는 빈 줄 하나.
- **각주 이름표**는 문서 전체를 보고 정한다.
  - 숫자 표시 `n`: 문서에서 처음 쓰이면 `n`, 이미 쓰였으면 `n-p<PDF쪽>`, 그것도 쓰였으면 `n-p<PDF쪽>-2`, `-3` …
  - 기호 표시: `p<PDF쪽>-s<쪽 안 순번>`.
  - 표시 없음: 그 쪽의 첫 각주이고 **바로 앞 PDF 쪽(p−1)에 각주가 있으면**, 그 쪽 마지막 각주의 이어짐으로 보고 그 정의 끝에 붙인다.
    그 밖에는 별개 각주 `p<PDF쪽>-u<쪽 안 순번>`. OCR이 번호를 놓친 다른 각주나 멀리 떨어진 쪽의 각주를 합치지 않기 위해서다.
- 정의: `[^4]: John Stuart Mill, …`. 두 번째 줄부터는 앞에 공백 4칸.
- **본문 참조:** 같은 쪽 paragraph 블록에서 `n)`을 처음 한 번 찾아 `[^이름표]`로 바꾼다.
  - 앞 글자가 있어야 한다(줄 맨 앞은 바꾸지 않는다). 허용하는 앞 글자: 한글 음절, 라틴 문자, 한자, `.`, `,`, `?`, `!`, 닫는 따옴표(`"”’'`), 닫는 괄호(`)」』]`).
  - 뒤 글자: 공백, 줄 끝, 문장부호.
  - 같은 줄에서 매칭 위치 앞에 닫히지 않은 `(`가 있으면 바꾸지 않는다.
  - 예: `금지했고,4) 장자크` → `금지했고,[^4] 장자크`.
  - 예: `(창 1:20-23), 여섯째`는 바꾸지 않는다(앞 글자 `-`). KCI 9쪽에서 이 줄과 각주 23이 같은 쪽에 실제로 있다.
  - 예: `(표1) 참조`는 바꾸지 않는다(닫히지 않은 `(`).
- 못 찾은 각주(숫자만 위첨자로 찍힌 학술지, 기호 각주, 표시 없는 각주)는 그 쪽 표시 줄 뒤에 붙인다: `[p. 713] [^9]`.
  GFM 등은 참조되지 않은 정의를 화면에 그리지 않으므로, 모든 정의는 반드시 한 번 참조된다.
- 정의는 모두 문서 끝에 둔다. 본문 끝에 빈 줄, 구분 줄 `<!-- footnotes -->`, 그 뒤에 정의들.

### split 워커

- 부모는 자식을 띄우기 전에 모델을 한 번 불러 본다. 모델이 없거나 깨졌으면 여기서 exit 4로 끝내고, 첫 실행의 시스템 컴파일도 부모에서 한 번만 일어난다(자식 10개가 동시에 컴파일하지 않게). 불러온 모델은 바로 놓는다.
- 자식은 `--md-pages-output chunk.json --page-range A-B`로 쪽 구조 데이터를 쓴다.
- 부모는 조각 JSON을 순서대로 읽어 이어 붙이고, 문서 조립 함수로 Markdown을 한 번 만든다. 출력 규칙(덮어쓰기 금지, 임시 파일 후 이동)은 단일 프로세스와 같다.
- 한 프로세스 안의 쪽 병렬 처리는 모델 하나를 같이 쓰고, 예측 호출은 잠금으로 한 번에 하나씩 한다.

## 모델 배포

- 모델: `hugging-mac/pp-doclayout-v3-coreml` 리비전 `270f90d8404e9ef88ce6293da80d4cf731586353` (FP16, Apache-2.0, 원본 `PaddlePaddle/PP-DocLayoutV3_safetensors`).
  라벨 순서는 원본 `inference.yml`의 `label_list`(25개)를 따른다. CoreML 변환본의 `id2label`은 이름이 합쳐져 있어 쓰지 않는다.
- 저장소에는 넣지 않는다(mlpackage 97MB, 컴파일본 88MB).
- `scripts/fetch-layout-model.sh`: 위 리비전의 파일 3개를 받고 SHA-256을 확인한 뒤 `xcrun coremlcompiler compile … --platform macos --deployment-target 26.0`으로 `.build/models/PPDocLayoutV3.mlmodelc`를 만든다.
  이미 있으면 받지 않는다. 끝에 개발용 `export APPLE_VISION_OCR_LAYOUT_MODEL=…` 줄을 출력한다. `.build/`는 이미 gitignore 대상이다.
  - `Manifest.json` `ffcc86c607a50e8e3d40b11964b0628442c13104b0fe8a43fe67ce5a3006e589`
  - `model.mlmodel` `699fc72be51534a9a2f64314767249000e3f5580e523d26d48262ef02e877eb2`
  - `weight.bin` `da3e08e77605d433b249910697e6c04a3dc05db6f6e3b2e35337e176a791a9c3`
- `scripts/package-vocr-app.sh`가 `fetch-layout-model.sh`를 먼저 부르고 컴파일본을 `VOCR.app/Contents/Resources/`에 넣는다. 릴리스 zip이 약 90MB 커진다.
- 모델 찾는 순서: 환경변수 `APPLE_VISION_OCR_LAYOUT_MODEL` → 실행 파일 경로(`resolvingSymlinksInPath()`로 푼 뒤)의 `../Resources/PPDocLayoutV3.mlmodelc`.
  `swift run`이나 `.build/*/apple-vision-ocr`로 개발할 때는 환경변수를 쓴다.
- 설치기 `install-vocr-quick-action.sh`:
  - 맨 처음에 `sw_vers -productVersion`의 주 버전이 26 미만이면 아무것도 바꾸지 않고 v1.3.1 안내를 출력한 뒤 0이 아닌 코드로 끝낸다(기존 앱 교체 전에).
  - `~/.local/bin/apple-vision-ocr`를 복사 대신 `ln -sf`로 앱 안 실행 파일을 가리키는 심볼릭 링크로 만든다. 그래야 설치된 CLI가 앱 안의 모델을 찾는다. 기존에 복사된 일반 파일도 `-f`로 바뀐다.
- 릴리스 `Install.command`: 설치기가 실패해도 키 입력을 기다린 뒤 닫는다(OS 버전 안내를 읽을 수 있게).
- `THIRD_PARTY_NOTICES.md`에 모델 출처와 Apache-2.0 고지를 넣고 `scripts/make-release-package.sh`가 zip에 복사한다.

## macOS 26

- `Package.swift`: `.macOS("26.0")`. tools-version은 5.9 그대로 둔다(6.x로 올리면 Swift 6 언어 모드가 켜진다).
- 앱 `LSMinimumSystemVersion` 26.0.
- CI: 바꾸지 않는다(`macos-latest`가 이미 `macos-26-arm64`).
- macOS 13을 적은 곳을 모두 바꾸고 "macOS 13~25는 v1.3.1" 링크를 단다: `README.md`, `README.ko.md`, `docs/user-guide.md`, `docs/user-guide.ko.md`, `docs/ai-install-and-setup.md`, `docs/architecture-and-modification-guide.md`, `CONTRIBUTING.md`, `scripts/make-release-package.sh`가 만드는 `README.txt`. `CURRENT_STATUS.md`에는 날짜를 붙인 기록으로 남긴다.
- 같은 문서들에 Markdown 출력 옵션, 각주 형식, 한계를 적는다(영어·한국어 쌍을 함께).
  `docs/ai-install-and-setup.md`와 아키텍처 가이드의 환경변수 표에 `APPLE_VISION_OCR_LAYOUT_MODEL`을 넣고, CLI 바이너리만 따로 복사하면 모델을 못 찾는다는 점을 적는다. `AGENTS.md`의 개발 명령에 `scripts/fetch-layout-model.sh`를 더한다.
- 버전 문자열(2.0.0)은 릴리스 단계에서 Release Checklist대로 바꾼다. 릴리스와 푸시는 사용자가 요청할 때만 한다.

## 이번에 하지 않는 것

- 같은 실행에서 Markdown과 PDF·TXT를 함께 내기.
- 소제목 단계(`##`/`###`) 구분, 문단 안 한글 줄 잇기.
- 모델을 직접 변환하기, 다른 레이아웃 모델(Heron) 대안.
- 2단 편집을 위한 별도 규칙(모델의 읽기 순서만 쓴다).
- GUI 출력 선택을 팝업 메뉴로 바꾸기(체크박스 하나만 더한다).

## 알려진 한계

- 여러 단에 걸친 그림이 있는 잡지형 다단 쪽은 읽기 순서가 틀릴 수 있다(관문 시험 3단 쪽 2개 중 1개). 일반 1단 논문에는 영향이 없다.
- 쪽 맨 아래 번호 목록(`1) …`)이 각주로 바뀔 수 있다(11번 규칙). 내용은 남는다.
- 본문 참조 자동 치환은 `n)` 형태만 한다. 나머지는 쪽 표시 뒤 참조로 간다.
- 쪽의 첫 각주가 번호를 잃었는데 실제로는 새 각주라면 앞 쪽 각주에 붙는다.
- 모델이 각주 하나를 두 상자로 나눠 두 번째 상자가 쪽 중간에 번호 없이 나오면, 실제로는 이어짐인데 별개 각주(`p<쪽>-u<n>`)가 되어 쪽 표시 뒤에서 참조된다. 내용은 남는다.
- 머리말을 모델이 놓쳤고 앞뒤 쪽 번호도 모르면(한 쪽만 돌릴 때 등) 머리말 줄이 쪽 맨 앞 문단으로 남는다.
- 로고 조각이 작게 읽히면(실측 `O`, 1.18배) 문단으로 남는다.
- 재OCR로 되살린 줄은 로고와 겹친 탓에 오자가 많을 수 있다.
- 여백 기준(위·아래 14%, 1.5배)은 실측한 학술지 3종에 맞춘 값이다.
- 첫 실행의 모델 컴파일(약 11초) 동안에는 취소가 바로 먹지 않는다.
- 모델은 개인이 올린 변환본이다. 해시로 고정했고 릴리스 zip에 컴파일본이 들어가므로 원 저장소가 사라져도 릴리스본은 남는다. 원본과의 정확도 비교는 이 문서의 실측 11쪽뿐이다.
- 이 기기는 macOS 27이라 macOS 26 실행은 직접 확인하지 못한다.

## 구현 첫 단계 (관문) — 2026-10-27 실시

1. 다단 읽기 순서: 3단 잡지 쪽 2개 중 1개 틀림. 말뭉치에 다단 쪽이 드물어(표본 148편 중 1편) 모델 순서를 그대로 쓰고 한계로 적었다.
2. 병합 셀 표(한국어): 통과.
3. KCI 5쪽 각주 4~9: 통과(재OCR 조각 규칙 추가).

결과는 "실험 근거"의 관문 시험 항목에 있다.

## 검증 기준

1. 단위 테스트(모델 없이 실행): 읽기 순서 계산(동점 포함), 좌표 변환, 줄 배정(삭제 영역과 겹친 각주 줄 보존), 여백 규칙, 영역 없는 쪽, 빈 영역 판정, 각주 표시 읽기, 제목 줄 잇기, `#` 이스케이프, 문서 조립.
   - 문서 조립 fixture: 번호가 다시 1부터 시작, 같은 쪽 같은 번호 두 개, `*` 각주, 번호 없는 각주(쪽 첫 각주와 중간), 바로 앞 쪽에서 이어지는 각주, 각주 없는 쪽을 건너뛴 번호 없는 각주(합치지 않음), 이어진 각주 첫 줄이 `1998, pp.`. 이름표 중복이 없고 모든 정의가 참조되면 통과.
   - 참조 치환 fixture: `(창 1:20-23), 여섯째`와 `(표1) 참조`는 바꾸지 않고, `설교인가?1)`은 바꾼다. 줄 맨 앞 `1) …`은 바꾸지 않는다.
   - 여백 fixture: 머리말·쪽번호 영역이 모두 없는 쪽의 머리말 줄이 이웃 쪽 번호로 지워지고 쪽번호가 채워진다. 이웃 번호가 없으면 남는다. 아래쪽 큰 로고 줄은 지워지고, 같은 위치의 보통 높이 각주 줄은 남는다.
2. CLI 규약 테스트: 금지 조합 exit 1, `.md`가 아닌 확장자 exit 1, 출력이 이미 있으면 exit 5, 모델이 없으면(`--dry-run` 포함) exit 4와 안내 메시지, stdout에 `.md` 경로 한 줄, split 자식 인자에 `--md-pages-output`.
3. 단일·split 동등성: 같은 파일을 단일 프로세스와 `--split-workers`로 돌린 Markdown이 바이트 단위로 같다. 조각 경계에 각주 이어짐이 걸리는 page-range로도 확인한다. `scripts/verify-equivalence.sh`에 Markdown 비교를 더한다.
   다르면 원인을 찾고, 모델 점수의 미세한 차이 때문이면 `computeUnits`를 고정해 다시 재고 결과를 보고한다.
4. 구조: 학술지 3종 전체에서
   - `#`이 하나이고 논문 제목과 같다.
   - `##` 목록이 PDF 글자층의 장·절 제목(`I.`, `II.`, `1.`, `2.` …)과 같다.
   - `[p. N]`이 빠짐없이 차례로 이어진다.
   - 각주 이름표가 1부터 마지막 번호까지 빠짐없이 이어지고, 각주 내용이 본문 문단에 섞여 있지 않다.
   - 본문의 `[^n]` 위치 10곳을 골라 PDF 글자층의 같은 자리에 `n)`이 있는지 대조한다.
   - 본문에 `kci.go`와 머리말 문장(예: `동물윤리의 역사와 현대적 과제 •`)이 없다.
5. 내용 보존: 학술지 3종 전체에서, 같은 설정의 TXT 출력에 있는 줄 중 Markdown에 없는 줄을 모두 뽑아 사람이 본다. 머리말, 쪽번호, 로고 조각만 있어야 한다.
   Markdown에만 있는 줄은 재OCR로 되살린 줄이어야 한다.
6. 실행 규약: SIGTERM 취소, GUI 일시정지·취소, GUI에서 Markdown을 고르면 다른 출력이 꺼지는지.
7. 회귀: 테스트 전용 `TMPDIR`(`TMPDIR=$(mktemp -d) swift test`)에서 기존 테스트 전부 통과. 40쪽 픽스처의 TXT 출력이 변경 전과 바이트 단위로 같고, PDF 출력은 쪽별 추출 텍스트가 같다.
8. 설치·패키지: 릴리스 패키지를 임시 `HOME`에 설치해 `~/.local/bin/apple-vision-ocr`가 심볼릭 링크인지, 기존 일반 파일 위에 재설치해도 되는지, 그 링크로 `--md-only --split-workers 2`가 되는지 확인한다. 모델이 든 앱이 `codesign --verify --deep --strict`를 통과한다.
9. 성능: KCI 25쪽 논문을 워커 10개로 돌린 시간과 최대 메모리를 TXT 모드와 비교해 기록한다. 무거운 부하라 **사용자 동의를 받은 뒤** 실행한다.
   모델 컴파일 캐시가 없는 상태에서 워커 10개로 첫 실행할 때의 지연도 한 번 잰다.
10. GUI에서 Markdown을 골라 실제 파일이 나오는지 확인한다.
