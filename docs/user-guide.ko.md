# Apple Vision OCR 사용자 가이드

[English](user-guide.md) | 한국어

Apple Vision OCR는 이미지만 포함된 PDF 페이지를 검색 가능한 PDF, 일반 텍스트 파일, 또는 둘 다로 변환합니다. Apple 내장 Vision 프레임워크를 사용하므로 macOS 로컬 환경에서 실행되며 문서를 외부로 업로드하지 않습니다.

## 준비 사항

- macOS 13 이상.
- PDF 파일. 이미지만 있는 스캔 문서가 주요 사용 사례입니다.
- 릴리스 패키지 사용 시: Apple Silicon Mac. 그 외에는 다른 것이 필요하지 않습니다.
- 소스에서 빌드 시: Xcode command line tools 또는 Xcode.

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

OCR 출력 파일이 이미 존재하는 경우 다른 `--output` 또는 `--txt-output` 경로를 지정합니다. CLI는 기존 파일을 덮어쓰지 않습니다.
