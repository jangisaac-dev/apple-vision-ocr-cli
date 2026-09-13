import Foundation

enum VOCRLanguage: Equatable {
    case english
    case korean

    static let resolved = resolve(
        environmentValue: ProcessInfo.processInfo.environment["VOCR_LANGUAGE"],
        preferredLanguages: Locale.preferredLanguages
    )

    static func resolve(environmentValue: String?, preferredLanguages: [String]) -> VOCRLanguage {
        switch environmentValue {
        case "en":
            return .english
        case "ko":
            return .korean
        default:
            return preferredLanguages.first?.lowercased().hasPrefix("ko") == true ? .korean : .english
        }
    }
}

struct VOCRLocalizedString {
    let english: String
    let korean: String

    var text: String {
        VOCRStrings.language == .english ? english : korean
    }
}

enum VOCRStrings {
    static var language = VOCRLanguage.resolved

    static let statusReady = VOCRLocalizedString(english: "Ready", korean: "준비됨")
    static let statusItemCompleted = VOCRLocalizedString(english: "VOCR Completed", korean: "VOCR 완료")
    static let statusItemFailed = VOCRLocalizedString(english: "VOCR Failed", korean: "VOCR 실패")
    static let statusItemCanceled = VOCRLocalizedString(english: "VOCR Canceled", korean: "VOCR 취소")
    static let menuShowDetails = VOCRLocalizedString(english: "Show Details", korean: "상세 창 보기")
    static let buttonPause = VOCRLocalizedString(english: "Pause", korean: "일시정지")
    static let buttonCancel = VOCRLocalizedString(english: "Cancel", korean: "취소")
    static let buttonResume = VOCRLocalizedString(english: "Resume", korean: "이어서 진행")
    static let buttonQuit = VOCRLocalizedString(english: "Quit", korean: "종료")
    static let statusCompleted = VOCRLocalizedString(english: "Completed", korean: "완료됨")
    static let statusFailed = VOCRLocalizedString(english: "Failed", korean: "실패")
    static let statusCanceled = VOCRLocalizedString(english: "Canceled", korean: "취소됨")
    static let messageNoPDFSelected = VOCRLocalizedString(english: "No PDF selected.", korean: "선택된 PDF가 없습니다.")
    static let messageJobStarted = VOCRLocalizedString(english: "Starting OCR job", korean: "OCR 작업 시작")
    static let messageOCRJobCanceled = VOCRLocalizedString(english: "OCR job canceled", korean: "OCR 작업 취소됨")
    static func messageOCRFile(_ fileName: String) -> String {
        language == .english ? "OCR \(fileName)" : "\(fileName) OCR"
    }
    static let pipelineStarting = VOCRLocalizedString(english: "Starting OCR", korean: "OCR 시작")
    static let pipelineRasterizingExistingText = VOCRLocalizedString(
        english: "Existing selectable text found; rasterizing affected pages",
        korean: "기존 선택 가능한 텍스트 발견; 해당 페이지 래스터화"
    )
    static let pipelineWritingOutput = VOCRLocalizedString(english: "Writing output", korean: "출력 저장")
    static let pipelineCompleted = VOCRLocalizedString(english: "Completed OCR", korean: "OCR 완료")
    static func pipelineRenderingPage(_ pageNumber: Int) -> String {
        language == .english ? "Rendering page \(pageNumber)" : "페이지 \(pageNumber) 렌더링"
    }
    static let pipelinePaused = VOCRLocalizedString(english: "Paused", korean: "일시정지")
    static func pipelineRecognizingPage(_ pageNumber: Int) -> String {
        language == .english ? "OCR page \(pageNumber)" : "페이지 \(pageNumber) OCR"
    }
    static func pipelineCompletedPage(_ pageNumber: Int) -> String {
        language == .english ? "Completed page \(pageNumber)" : "페이지 \(pageNumber) 완료"
    }
    static func pipelineMessage(_ coreMessage: String) -> String {
        switch coreMessage {
        case pipelineStarting.english:
            return pipelineStarting.text
        case pipelineRasterizingExistingText.english:
            return pipelineRasterizingExistingText.text
        case pipelineWritingOutput.english:
            return pipelineWritingOutput.text
        case pipelineCompleted.english:
            return pipelineCompleted.text
        case pipelinePaused.english:
            return pipelinePaused.text
        default:
            if coreMessage.hasPrefix("Rendering page "),
               let pageNumber = Int(coreMessage.dropFirst("Rendering page ".count)) {
                return pipelineRenderingPage(pageNumber)
            }
            if coreMessage.hasPrefix("OCR page "),
               let pageNumber = Int(coreMessage.dropFirst("OCR page ".count)) {
                return pipelineRecognizingPage(pageNumber)
            }
            if coreMessage.hasPrefix("Completed page "),
               let pageNumber = Int(coreMessage.dropFirst("Completed page ".count)) {
                return pipelineCompletedPage(pageNumber)
            }
            return coreMessage
        }
    }
    static func logWorkerCountChanged(_ count: Int) -> String {
        language == .english
            ? "Worker process count changed: \(count)"
            : "동시 워커 프로세스 수 변경: \(count)개"
    }
    static func messageWorkerCount(_ count: Int) -> String {
        language == .english
            ? "\(count) worker processes"
            : "동시 워커 프로세스 \(count)개"
    }
    static let messagePauseRequested = VOCRLocalizedString(english: "Pause requested", korean: "일시정지 요청됨")
    static let messageCancelRequested = VOCRLocalizedString(english: "Cancel requested", korean: "취소 요청됨")
    static let logCLINotFoundSingleProcess = VOCRLocalizedString(
        english: "apple-vision-ocr CLI not found; running as a single process.",
        korean: "apple-vision-ocr CLI를 찾지 못해 단일 프로세스로 실행합니다."
    )
    static func logFileStarted(_ fileName: String) -> String {
        language == .english ? "Starting: \(fileName)" : "시작: \(fileName)"
    }
    static func messageFileCompleted(_ fileName: String) -> String {
        language == .english ? "Completed: \(fileName)" : "완료: \(fileName)"
    }
    static let messageOCRJobCompleted = VOCRLocalizedString(english: "OCR job completed", korean: "OCR 작업 완료")
    static let checkboxExtractText = VOCRLocalizedString(english: "Extract TXT", korean: "TXT 추출")
    static let checkboxInsertPageSeparators = VOCRLocalizedString(english: "Insert page separators", korean: "Page 구분자 넣기")
    static let checkboxGenerateSearchablePDF = VOCRLocalizedString(english: "Generate Searchable PDF", korean: "Searchable PDF 생성")
    static let checkboxDisableLanguageCorrection = VOCRLocalizedString(
        english: "Disable language correction (Speed first)",
        korean: "언어 보정 끄기 (속도 우선)"
    )
    static let checkboxRunInBackground = VOCRLocalizedString(
        english: "Switch to background after starting",
        korean: "시작 후 백그라운드로 전환"
    )
    static let buttonStart = VOCRLocalizedString(english: "Start", korean: "시작")
    static func logPlannedOutput(_ fileName: String) -> String {
        language == .english ? "Planned output: \(fileName)" : "출력 예정: \(fileName)"
    }
    static let labelSubtitle = VOCRLocalizedString(
        english: "Generates only the required outputs for selected PDFs.",
        korean: "선택한 PDF에 대해 필요한 출력만 생성합니다."
    )
    static let headerSelectedFiles = VOCRLocalizedString(english: "Selected files", korean: "선택 파일")
    static let headerOutputOptions = VOCRLocalizedString(english: "Output options", korean: "출력 방식")
    static let headerWorkerProcessCount = VOCRLocalizedString(english: "Worker process count", korean: "동시 워커 프로세스 수")
    static let headerRecognitionMode = VOCRLocalizedString(english: "Recognition mode", korean: "인식 모드")
    static let popupRecognitionAccuracyFirst = VOCRLocalizedString(english: "Accuracy first", korean: "정확도 우선")
    static let popupRecognitionSpeedFirst = VOCRLocalizedString(english: "Speed first (English only)", korean: "속도 우선 (영문 전용)")
    static let headerRenderScale = VOCRLocalizedString(english: "Korean speed/quality", korean: "한국어 속도/품질")
    static let popupRenderScaleQuality = VOCRLocalizedString(english: "Quality first (2.0x)", korean: "품질 우선 (2.0x)")
    static let popupRenderScaleBalanced = VOCRLocalizedString(english: "Balanced Korean speed (1.5x)", korean: "한국어 속도 균형 (1.5x)")
    static let popupRenderScaleFastDraft = VOCRLocalizedString(english: "Fast draft (1.25x)", korean: "빠른 초안 (1.25x)")
    static let placeholderNoPDFFiles = VOCRLocalizedString(english: "No PDF files were provided.", korean: "PDF 파일이 전달되지 않았습니다.")
    static let validationMissingOutput = VOCRLocalizedString(
        english: "Select at least one of Extract TXT or Generate Searchable PDF.",
        korean: "TXT 추출 또는 Searchable PDF 생성 중 하나 이상을 선택하세요."
    )
    static func previewGeneratedFiles(_ files: String) -> String {
        language == .english ? "Generated files: \(files)" : "생성 파일: \(files)"
    }
    static let previewPageSeparator = VOCRLocalizedString(
        english: " · Separator: ===== Page N =====",
        korean: " · 구분자: ===== Page N ====="
    )
    static let logSpeedFirstKoreanUnsupported = VOCRLocalizedString(
        english: "Speed first does not currently support Korean recognition in Apple Vision. Run with Accuracy first.",
        korean: "속도 우선은 현재 Apple Vision에서 한국어 인식을 지원하지 않습니다. 정확도 우선으로 실행하세요."
    )
    static func logJobStartedWithOptions(
        recognitionLevel: String,
        renderScale: Double,
        workerCount: Int
    ) -> String {
        language == .english
            ? "Job started: \(recognitionLevel) · render \(renderScale)x · \(workerCount) worker processes"
            : "작업 시작: \(recognitionLevel) · 렌더 \(renderScale)x · 동시 워커 프로세스 \(workerCount)개"
    }
    static let logPageBreaksRequireText = VOCRLocalizedString(
        english: "Page separators require Extract TXT to be selected.",
        korean: "Page 구분자는 TXT 추출을 선택해야 사용할 수 있습니다."
    )
    static func logInvalidParallelism(minimumCount: Int, maximumCount: Int) -> String {
        language == .english
            ? "Worker process count must be between \(minimumCount) and \(maximumCount)."
            : "동시 워커 프로세스 수는 \(minimumCount)-\(maximumCount) 사이여야 합니다."
    }
    static func logExistingTextInspectionFailed(fileName: String, errorDescription: String) -> String {
        language == .english
            ? "Failed to inspect existing text: \(fileName) · \(errorDescription)"
            : "기존 텍스트 검사 실패: \(fileName) · \(errorDescription)"
    }
    static let alertExistingTextMessage = VOCRLocalizedString(
        english: "Some PDFs already contain selectable text.",
        korean: "이미 선택 가능한 텍스트가 있는 PDF가 있습니다."
    )
    static func alertExistingTextFileDetail(fileName: String, pageCount: Int) -> String {
        language == .english ? "\(fileName): \(pageCount) page(s)" : "\(fileName): \(pageCount)페이지"
    }
    static func alertExistingTextBody(detail: String, omittedCount: Int) -> String {
        let omittedFiles = omittedCount > 0 ? alertMoreFiles(omittedCount) : ""
        return language == .english ? """
Continuing will flatten those pages to images and overlay new OCR text.
This avoids duplicate selection of existing searchable text. The original PDF is not modified.

\(detail)\(omittedFiles)
""" : """
계속 진행하면 해당 페이지를 이미지로 평탄화한 뒤 새 OCR 텍스트만 다시 얹습니다.
이렇게 하면 기존 searchable 텍스트가 중복 선택되는 문제를 피할 수 있습니다. 원본 PDF는 변경하지 않습니다.

\(detail)\(omittedFiles)
"""
    }

    static func alertMoreFiles(_ omittedCount: Int) -> String {
        language == .english ? "\nand \(omittedCount) more files" : "\n외 \(omittedCount)개 파일"
    }

    static let buttonContinue = VOCRLocalizedString(english: "Continue", korean: "계속 진행")
    static let logSelectPDFInFinder = VOCRLocalizedString(
        english: "Select PDF files in Finder, then run Apple Vision OCR.",
        korean: "Finder에서 PDF 파일을 선택한 뒤 Apple Vision OCR을 실행하세요."
    )

    static let all: [String: VOCRLocalizedString] = [
        "statusReady": statusReady,
        "statusItemCompleted": statusItemCompleted,
        "statusItemFailed": statusItemFailed,
        "statusItemCanceled": statusItemCanceled,
        "menuShowDetails": menuShowDetails,
        "buttonPause": buttonPause,
        "buttonCancel": buttonCancel,
        "buttonResume": buttonResume,
        "buttonQuit": buttonQuit,
        "statusCompleted": statusCompleted,
        "statusFailed": statusFailed,
        "statusCanceled": statusCanceled,
        "messageNoPDFSelected": messageNoPDFSelected,
        "messageJobStarted": messageJobStarted,
        "messageOCRJobCanceled": messageOCRJobCanceled,
        "pipelineStarting": pipelineStarting,
        "pipelineRasterizingExistingText": pipelineRasterizingExistingText,
        "pipelineWritingOutput": pipelineWritingOutput,
        "pipelineCompleted": pipelineCompleted,
        "pipelinePaused": pipelinePaused,
        "messagePauseRequested": messagePauseRequested,
        "messageCancelRequested": messageCancelRequested,
        "logCLINotFoundSingleProcess": logCLINotFoundSingleProcess,
        "messageOCRJobCompleted": messageOCRJobCompleted,
        "checkboxExtractText": checkboxExtractText,
        "checkboxInsertPageSeparators": checkboxInsertPageSeparators,
        "checkboxGenerateSearchablePDF": checkboxGenerateSearchablePDF,
        "checkboxDisableLanguageCorrection": checkboxDisableLanguageCorrection,
        "checkboxRunInBackground": checkboxRunInBackground,
        "buttonStart": buttonStart,
        "labelSubtitle": labelSubtitle,
        "headerSelectedFiles": headerSelectedFiles,
        "headerOutputOptions": headerOutputOptions,
        "headerWorkerProcessCount": headerWorkerProcessCount,
        "headerRecognitionMode": headerRecognitionMode,
        "popupRecognitionAccuracyFirst": popupRecognitionAccuracyFirst,
        "popupRecognitionSpeedFirst": popupRecognitionSpeedFirst,
        "headerRenderScale": headerRenderScale,
        "popupRenderScaleQuality": popupRenderScaleQuality,
        "popupRenderScaleBalanced": popupRenderScaleBalanced,
        "popupRenderScaleFastDraft": popupRenderScaleFastDraft,
        "placeholderNoPDFFiles": placeholderNoPDFFiles,
        "validationMissingOutput": validationMissingOutput,
        "previewPageSeparator": previewPageSeparator,
        "logSpeedFirstKoreanUnsupported": logSpeedFirstKoreanUnsupported,
        "logPageBreaksRequireText": logPageBreaksRequireText,
        "alertExistingTextMessage": alertExistingTextMessage,
        "buttonContinue": buttonContinue,
        "logSelectPDFInFinder": logSelectPDFInFinder
    ]
}
