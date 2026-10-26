# Apple Vision OCR 사용자 가이드

[English](user-guide.md) | 한국어

Apple Vision OCR는 이미지만 포함된 PDF 페이지를 검색 가능한 PDF, 일반 텍스트 파일, 또는 둘 다로 변환합니다. Apple 내장 Vision 프레임워크를 사용하므로 macOS 로컬 환경에서 실행되며 문서를 외부로 업로드하지 않습니다.

## 준비 사항

- macOS 26 이상 (Apple Silicon).
- macOS 13~25 사용자는 [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1)을 계속 사용해야 합니다.
- PDF 파일. 이미지만 있는 스캔 문서가 주요 사용 사례입니다.
- 릴리스 패키지 사용 시: Apple Silicon Mac. 그 외에는 다른 것이 필요하지 않습니다.
- 소스에서 빌드 시: Xcode command line tools 또는 Swift 5.9 이상이 포함된 Xcode.

별도의 빌드 과정 없이 Finder Quick Action을 사용하려면 [GitHub Releases](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases) 페이지에서 `VOCR-<version>-macos-arm64.zip`을 다운로드하여 압축을 풀고 `Install.command`를 더블 클릭합니다. macOS에서 실행을 차단하는 경우 시스템 설정 > 개인정보 보호 및 보안(System Settings > Privacy & Security)을 열고 "그래도 열기"(Open Anyway)를 클릭합니다. 패키지에 포함된 `README.txt`에 터미널을 이용한 대안과 설치 제거(uninstall) 단계가 안내되어 있습니다.

소스에서 빌드할 때 `swift`를 사용할 수 없다면 Xcode command line tools를 설치합니다:

```bash
xcode-select --install
```

## 빠른 시작

프로젝트를 클론하고 체크아웃한 디렉터리에서 바로 OCR을 실행합니다:

```bash
git clone https://github.com/jangisaac-dev/apple-vision-ocr-cli.git
cd apple-vision-ocr-cli
swift run apple-vision-ocr path/to/input.pdf
```

기본 출력 파일은 입력 파일과 같은 위치에 생성됩니다:

```text
input.pdf -> input_ocr.pdf
```

원본 PDF는 절대 변경되지 않습니다. 이미 존재하는 출력 파일은 덮어쓰지 않습니다.

## 텍스트 출력

텍스트 파일만 생성하는 경우:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt-only
```

검색 가능한 PDF와 텍스트 파일을 둘 다 생성하는 경우:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt
```

텍스트 출력에 페이지 구분자를 추가하는 경우:

```bash
swift run apple-vision-ocr path/to/input.pdf --txt-only --page-breaks
```

텍스트 출력 경로를 직접 지정하는 경우:

```bash
swift run apple-vision-ocr path/to/input.pdf \
  --txt-only \
  --txt-output output.txt
```

## Markdown 출력

레이아웃 구분 Markdown 출력은 문서 제목, 소제목, 본문, 표, 각주가 섞이지 않도록 구조화된 Markdown 문서를 생성합니다.

### 출력 내용

- **제목**: 논문 또는 문서 제목을 `# 제목` 형식으로 출력합니다.
- **소제목**: 장·절 소제목을 `## 소제목` 형식으로 출력합니다(소제목 단계는 구분하지 않고 모두 `##`로 통일).
- **쪽 표시**: 페이지마다 상단에 쪽 번호 표시를 추가합니다. 인쇄된 쪽 번호가 인식되면 `[p. 713]`, 인식되지 않으면 `[PDF p. 5]`로 표시합니다.
- **본문**: OCR 줄바꿈을 유지한 문단 블록입니다. 본문 줄이 `#`으로 시작하면 `\#`로 이스케이프합니다.
- **표**: Vision 프레임워크의 문서 분석(`RecognizeDocumentsRequest`)으로 표 구조를 분석하여 Markdown 표로 변환합니다.
- **각주**: 본문에서 각주 번호(예: `n)`)를 찾아 인라인 각주 참조 `[^4]`로 연결합니다(본문에서 위치를 찾지 못한 경우 쪽 표시 줄 뒤에 `[p. 713] [^4]`로 첨부). 모든 각주 정의는 문서 끝의 `<!-- footnotes -->` 구분선 뒤에 모아 배치합니다.
- **머리말/꼬리말/로고 제거**: 머리말, 쪽번호, 꼬리말, KCI 워터마크 등의 로고 영역은 자동으로 걸러냅니다.
- **빈 영역 재OCR**: 로고 등에 가려 쪽 전체 OCR에서 누락된 각주나 본문 등의 빈 영역은 상자를 잘라 다시 OCR하여 복원합니다.

출력 예시:

```markdown
[p. 713]

은 기계적 반응이라고 폄하하였다. ... 동물 학대를 금지했고,[^4] ...

## 2. 피터 싱어(Peter Singer)의 동물윤리

피터 싱어(Peter Singer)는 ...

<!-- footnotes -->

[^4]: John Stuart Mill, On Liberty and the Subjection of Women, ...
```

### CLI 사용법

기본 대상 경로(`<입력이름>.md`)로 Markdown 출력:

```bash
swift run apple-vision-ocr path/to/input.pdf --md-only
```

원하는 경로를 지정하여 Markdown 출력:

```bash
swift run apple-vision-ocr path/to/input.pdf --md-output output.md
```

멀티프로세스 분할 워커와 함께 사용:

```bash
swift run apple-vision-ocr path/to/input.pdf --md-only --split-workers 4
```

Markdown 출력 옵션은 `--output`, `--txt`, `--txt-only`, `--txt-output`, `--page-breaks`와 동시에 사용할 수 없습니다(종료 코드 1). `--split-workers`, `--page-range`, `--lang`, `--recognition-level`, `--render-scale`, `--no-language-correction`, `--dry-run` 옵션은 문제없이 함께 동작합니다.

### GUI 사용법

`VOCR.app`에서 **Markdown (레이아웃 구분)** / **Markdown (layout)** 체크박스를 선택합니다. 이 옵션을 켜면 TXT 추출, Page 구분자 넣기, Searchable PDF 생성 옵션이 자동으로 꺼지고 비활성화됩니다.

### 레이아웃 모델 안내

레이아웃 분석에는 CoreML 기반 `PP-DocLayoutV3` 모델(~90 MB, Apache-2.0, `THIRD_PARTY_NOTICES.md` 참고)이 사용됩니다.
- 패키징된 앱에서는 `VOCR.app/Contents/Resources/PPDocLayoutV3.mlmodelc`에 번들되어 있습니다.
- `~/.local/bin/apple-vision-ocr`에 설치된 CLI는 앱 내부를 가리키는 심볼릭 링크이므로 번들 모델을 자동으로 찾습니다. CLI 바이너리만 별도로 복사한 경우 환경 변수로 경로를 지정해야 합니다:
  ```bash
  export APPLE_VISION_OCR_LAYOUT_MODEL=/path/to/PPDocLayoutV3.mlmodelc
  ```
- 소스에서 개발하는 경우 다음 스크립트로 모델을 내려받아 컴파일할 수 있습니다:
  ```bash
  scripts/fetch-layout-model.sh
  ```

### 알려진 한계

- **다단 잡지 편집**: 그림이나 표가 여러 단에 걸쳐 있는 잡지형 다단 문서는 읽기 순서가 맞지 않을 수 있습니다.
- **본문 각주 참조 연결**: `n)` 형태의 숫자 표기만 본문 내에서 인라인 치환됩니다. 기호형 각주나 다른 형태의 표기는 해당 쪽 표시 줄(예: `[p. 713] [^9]`) 뒤에 참조가 붙습니다.
- **쪽 맨 아래 번호 목록**: 쪽 맨 하단에 위치한 번호 목록(`1) ...`)이 간혹 각주로 분류될 수 있습니다.
- **로고 아래 복원 텍스트**: 로고와 겹쳐 재OCR로 복원한 텍스트는 오자가 포함될 수 있습니다.
- **소제목 단계 미구분**: 장·절의 위계 구분 없이 모든 소제목은 `##`로 표시됩니다.

## 한국어 및 영어 OCR

기본 언어 목록은 한국어와 영어입니다:

```text
ko,en
```

언어를 명시적으로 지정할 수 있습니다:

```bash
swift run apple-vision-ocr path/to/input.pdf --lang ko,en
swift run apple-vision-ocr english.pdf --lang en
```

테스트된 macOS 버전 기준으로 Apple Vision의 `fast` 인식 모드는 한국어를 지원하지 않습니다. 한국어 문서 또는 한국어/영어 혼용 문서에는 기본값인 `accurate` 모드를 사용합니다.

영어 전용 문서에는 `fast` 모드를 사용할 수 있습니다:

```bash
swift run apple-vision-ocr english.pdf \
  --lang en \
  --recognition-level fast
```

## 대용량 문서

대규모 OCR 작업의 경우, 분할 워커(split workers)를 사용하면 최종 출력의 페이지 순서를 유지하면서 소요 시간(wall time)을 단축할 수 있습니다:

```bash
swift run apple-vision-ocr large.pdf \
  --txt-only \
  --split-workers 12 \
  --render-scale 2.0
```

`--split-workers` (2-16)는 `--page-breaks` 사용 여부와 관계없이 텍스트 전용 출력, 검색 가능한 PDF 출력, 그리고 둘 다 생성하는 경우(`--txt`) 모두에 적용됩니다. PDF의 경우 각 워커가 담당 페이지 범위에 대해 부분 검색 가능 PDF를 생성하고, 부모 프로세스가 이를 페이지 순서대로 병합하여 검색 가능한 텍스트 레이어를 유지합니다. 참고: 프로세스 내 `--page-parallelism`만으로는 속도가 빨라지지 않습니다. Apple Vision은 단일 프로세스 내에서 인식을 직렬화하므로, 실제로 여러 코어를 활용하려면 `--split-workers`를 사용해야 합니다. 18코어 머신 기준으로는 약 12개 워커가 최적의 성능을 보입니다.

문서의 일부분만 필요한 경우:

```bash
swift run apple-vision-ocr large.pdf \
  --txt-only \
  --page-range 1-100
```

## Finder Quick Action

현재 macOS 사용자를 위해 앱, CLI, Finder Quick Action을 설치합니다:

```bash
scripts/install-vocr-quick-action.sh
```

기본 설치 경로:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

설치 후 Finder에서 하나 이상의 PDF 파일을 선택하고 마우스 우클릭한 뒤 다음을 선택합니다:

```text
Apple Vision OCR
```

GUI는 macOS 언어를 따릅니다: 기본은 영어, 시스템 언어가 한국어면 한국어. 앱에서 다음을 선택할 수 있습니다:

```text
Markdown (레이아웃 구분)
TXT 추출
Searchable PDF 생성
Page 구분자 넣기
```

OCR이 실행되는 동안 메뉴 막대 아이콘에 진행 상황이 표시됩니다. 세부 정보 창을 닫아도 메뉴 막대에서 작업이 계속 실행됩니다.

## 사용자 정의 설치 경로

앱 및 바이너리 설치 경로는 원하는 대로 지정할 수 있습니다:

```bash
VOCR_APP_INSTALL_DIR="$HOME/Applications" \
VOCR_BIN_DIR="$HOME/.local/bin" \
scripts/install-vocr-quick-action.sh
```

Finder 워크플로는 항상 현재 사용자의 다음 경로에 설치됩니다:

```text
~/Library/Services/Apple Vision OCR.workflow
```

## 로그 및 진행 상황 파일

Finder Quick Action 로그:

```text
~/Library/Logs/vocr-quick-action.log
```

메뉴 막대 진행 상황 스냅샷:

```text
~/Library/Application Support/VOCR/progress/latest.json
```

## 문제 해결

`swift`가 없는 경우 Xcode command line tools를 설치합니다:

```bash
xcode-select --install
```

`--recognition-level fast`를 지정한 한국어 OCR이 실패할 경우, `fast` 모드를 제거하거나 `--lang en`으로 영어 전용 입력에만 사용합니다.

Finder에 Quick Action이 표시되지 않는 경우 설치 스크립트를 다시 실행한 뒤 워크플로가 존재하는지 확인합니다:

```bash
ls "$HOME/Library/Services/Apple Vision OCR.workflow"
```

macOS 26 미만 버전 환경에서는 [v1.3.1](https://github.com/jangisaac-dev/apple-vision-ocr-cli/releases/tag/v1.3.1) 릴리스를 사용하세요.

Markdown OCR 실행 중 종료 코드 4(`layout model not found`)가 발생하는 경우 `scripts/fetch-layout-model.sh`를 실행하여 모델을 빌드하거나, `APPLE_VISION_OCR_LAYOUT_MODEL` 환경 변수에 `PPDocLayoutV3.mlmodelc` 경로를 지정합니다. CLI 실행 파일은 `VOCR.app` 내부를 가리키는 심볼릭 링크 상태여야 번들 모델을 정상 탐색할 수 있습니다.

OCR 출력 파일이 이미 존재하는 경우 다른 `--output`, `--txt-output`, `--md-output` 경로를 지정합니다. CLI는 기존 파일을 덮어쓰지 않습니다.
