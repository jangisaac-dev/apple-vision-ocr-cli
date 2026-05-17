# 이미지 속 페이지 기준 OCR 및 일부 페이지 작업 기획안

## 요약

- 현재 VOCR의 페이지 기준은 PDF 파일의 물리 페이지 번호입니다. 사용자가 원하는 기준은 스캔 이미지 안에 인쇄된 책/자료의 실제 페이지 번호입니다.
- 구현 핵심은 각 PDF 페이지를 렌더링한 뒤, 하단/상단 영역에서 OCR로 인쇄 페이지 번호를 감지하고 `PDF page -> printed page` 매핑 테이블을 만드는 것입니다.
- 일부 페이지만 작업하는 기능은 이 매핑 테이블 위에 올려야 합니다. 사용자는 `1-20`, `서론-3장`, `printed 42-57` 같은 표현을 입력하고, 내부적으로는 실제 PDF page 목록으로 정규화합니다.
- 첫 버전은 자동 감지 + 수동 보정 UI 조합이 안전합니다. 스캔 품질, 로마 숫자, 장 제목, 빈 페이지 때문에 완전 자동만으로는 오작동 가능성이 높습니다.
- 이 기능은 OCR 실행 전 별도 "페이지 분석" 단계가 필요합니다. 분석 결과는 캐시해서 같은 PDF에서 반복 작업할 때 다시 OCR하지 않도록 합니다.

## 목표

1. PDF 물리 페이지 번호가 아니라 이미지 안에 보이는 인쇄 페이지 번호를 기준으로 작업 범위를 지정한다.
2. 전체 PDF가 아니라 사용자가 지정한 일부 페이지만 TXT 추출, searchable PDF 생성, page 구분 TXT 생성에 사용할 수 있게 한다.
3. 자동 감지 결과가 틀릴 수 있으므로 수동 보정과 미리보기를 제공한다.
4. 기존 원본 PDF는 계속 수정하지 않는다.

## 비목표

- 이번 단계에서 바로 구현하지 않는다.
- 책 구조 분석, 장/절 자동 분류, 목차 기반 자동 선택까지 한 번에 포함하지 않는다.
- 내부 이미지 페이지 번호가 없는 자료에 억지로 페이지 번호를 추론하지 않는다.

## 데이터 모델

```swift
struct PageIdentity {
    let pdfPageNumber: Int
    let printedPageLabel: String?
    let printedPageNumber: Int?
    let confidence: Double
    let source: PageIdentitySource
}

enum PageIdentitySource {
    case detected
    case userCorrected
    case missing
}

struct PageSelection {
    let requestedExpression: String
    let resolvedPDFPages: [Int]
    let unresolvedTerms: [String]
}
```

`printedPageLabel`은 `i`, `iv`, `A-12`, `부록 3` 같은 문자열을 보존합니다. 숫자 범위 비교가 가능한 경우에만 `printedPageNumber`를 채웁니다.

## 페이지 번호 감지 전략

1. PDF 페이지를 기존 `PDFRenderer`로 이미지화한다.
2. 페이지 번호가 흔히 있는 영역만 crop한다.
   - 하단 중앙
   - 하단 좌/우
   - 상단 좌/우
   - 상단 중앙
3. crop 영역별로 Apple Vision OCR을 빠른 모드로 실행한다.
4. 결과에서 페이지 번호 후보를 추출한다.
   - 아라비아 숫자: `12`, `- 12 -`, `p.12`
   - 로마 숫자: `iv`, `xii`
   - 접두어/접미어 포함: `12쪽`, `Page 12`
5. 이전/다음 페이지와 연속성을 비교해 가장 그럴듯한 후보를 고른다.
6. 낮은 confidence이거나 연속성이 깨지는 구간은 UI에서 보정 대상으로 표시한다.

## 수동 보정 UI

상세 창에 별도 단계로 `페이지 분석` 버튼을 둔다.

- 분석 결과 목록:
  - PDF page
  - 감지된 이미지 속 page
  - confidence
  - 상태: 정상 / 확인 필요 / 없음
- 사용자는 첫 페이지의 인쇄 페이지 번호를 직접 지정할 수 있다.
- 연속 구간이면 `이 페이지부터 +1씩 적용` 같은 보정 액션을 제공한다.
- 보정 결과는 PDF 파일 경로, 파일 크기, 수정일, page count 해시와 함께 캐시한다.

## 일부 페이지 작업

사용자 입력은 두 계층으로 받는다.

1. PDF page 기준:
   - `pdf:1-3,10,20-22`
2. 이미지 속 인쇄 page 기준:
   - `printed:1-20`
   - 기본 모드를 printed로 둘 경우 `1-20`도 printed page로 해석 가능

내부 실행 직전에는 항상 `resolvedPDFPages`로 변환한다. 이후 pipeline은 전체 page loop가 아니라 이 목록만 처리한다.

## 출력 방식별 처리

TXT 출력:
- 선택된 PDF page만 OCR한다.
- page 구분자를 켠 경우 구분자에는 설정에 따라 `===== Page 12 =====` 또는 `===== PDF Page 8 / Printed Page 12 =====`를 사용할 수 있다.

Searchable PDF 생성:
- 두 가지 정책 중 하나를 선택해야 한다.
  - 선택 페이지만 포함한 새 PDF 생성
  - 원본 전체 페이지를 유지하고 선택 페이지만 OCR overlay 갱신
- 사용자 기대는 대체로 "선택한 페이지만 작업"이므로 첫 버전은 선택 페이지만 포함한 새 PDF가 명확하다.

TXT + Searchable PDF:
- 같은 `resolvedPDFPages`를 공유해 결과가 서로 어긋나지 않게 한다.

## 위험 요소

- 스캔 자료에서 페이지 번호가 잘려 있거나 흐릴 수 있다.
- 머리말/목차는 로마 숫자, 본문은 아라비아 숫자인 경우가 흔하다.
- 양면 스캔에서 좌/우 페이지 번호 위치가 번갈아 바뀐다.
- PDF page 하나에 책의 두 페이지가 들어 있는 펼침면 스캔은 별도 split 판단이 필요하다.
- OCR이 본문 숫자를 페이지 번호로 오인할 수 있다.

## 권장 구현 순서

1. `PageSelection` 파서부터 만든다.
   - `1-3, 7, 10-12`
   - 잘못된 표현의 에러 메시지
2. pipeline이 `selectedPDFPages`를 받아 해당 페이지만 처리하게 한다.
3. PDF page 기준 일부 페이지 작업을 먼저 완성한다.
4. 그 다음 이미지 속 인쇄 page 감지기를 추가한다.
5. 감지 결과 캐시와 수동 보정 UI를 추가한다.
6. 마지막으로 printed page 기준 선택을 UI 기본 옵션으로 노출한다.

## 검증 계획

- 단위 테스트:
  - page expression parser
  - printed page mapping resolver
  - 로마 숫자/아라비아 숫자 변환
  - 선택 page만 pipeline에 전달되는지 확인
- fixture PDF:
  - 표지 때문에 PDF page와 printed page가 어긋나는 PDF
  - 로마 숫자 머리말 PDF
  - 페이지 번호가 없는 이미지-only PDF
  - 펼침면 스캔 PDF
- 수동 검증:
  - 사용자가 지정한 printed page 범위와 실제 출력 TXT/PDF page 수 비교
  - page 구분자가 기대한 기준으로 찍히는지 확인
