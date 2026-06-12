import AppKit
import AppleVisionOCRCore

final class VOCRWindowController: NSWindowController, NSWindowDelegate {
    static var defaultWorkerCount: Int {
        min(OCRJobParallelism.maximumCount, max(2, ProcessInfo.processInfo.activeProcessorCount * 2 / 3))
    }

    var onStart: (OCRJobOutputSelection, OCRJobParallelism, OCRRecognitionLevel, OCRRenderScale, Bool) -> Void = { _, _, _, _, _ in }
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onCancel: () -> Void = {}
    var onParallelismChange: (OCRJobParallelism) -> Void = { _ in }
    var onWindowWillClose: () -> Void = {}
    var onQuit: () -> Void = {}

    private let files: [URL]
    private var currentState: VOCRRunState = .idle
    private let textPresenceDetector = PDFTextPresenceDetector()

    private let fileListField = NSTextField(wrappingLabelWithString: "")
    private let outputPreviewField = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "준비됨")
    private let logView = NSTextView()
    private let textCheckbox = NSButton(checkboxWithTitle: "TXT 추출", target: nil, action: nil)
    private let pageBreakCheckbox = NSButton(checkboxWithTitle: "Page 구분자 넣기", target: nil, action: nil)
    private let pdfCheckbox = NSButton(checkboxWithTitle: "Searchable PDF 생성", target: nil, action: nil)
    private let recognitionLevelPopup = NSPopUpButton()
    private let renderScalePopup = NSPopUpButton()
    private let parallelismStepper = NSStepper()
    private let parallelismValueField = NSTextField(labelWithString: "\(VOCRWindowController.defaultWorkerCount)")
    private let runInBackgroundCheckbox = NSButton(checkboxWithTitle: "시작 후 백그라운드로 전환", target: nil, action: nil)
    private let startButton = NSButton(title: "시작", target: nil, action: nil)
    private let pauseButton = NSButton(title: "일시정지", target: nil, action: nil)
    private let cancelButton = NSButton(title: "취소", target: nil, action: nil)
    private let quitButton = NSButton(title: "종료", target: nil, action: nil)

    init(files: [URL]) {
        self.files = files
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VOCR - Apple Vision OCR"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
        updateFileList()
        updateOutputControls()
        updateControls(for: .idle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func appendLog(_ message: String) {
        let line = "[\(Self.timeFormatter.string(from: Date()))] \(message)\n"
        logView.textStorage?.append(NSAttributedString(string: line))
        logView.scrollToEndOfDocument(nil)
    }

    func noteOutput(_ output: VOCRJobOutput) {
        var lines = ["출력 예정: \(output.inputURL.lastPathComponent)"]
        if let textOutputURL = output.textOutputURL {
            lines.append("TXT: \(textOutputURL.lastPathComponent)")
        }
        if let pdfOutputURL = output.pdfOutputURL {
            lines.append("PDF: \(pdfOutputURL.lastPathComponent)")
        }
        appendLog(lines.joined(separator: " · "))
    }

    func updateProgress(_ snapshot: VOCRProgressSnapshot) {
        currentState = snapshot.state
        progressIndicator.doubleValue = Double(snapshot.percent)
        progressLabel.stringValue = "\(snapshot.percent)% · \(snapshot.message)"
        updateControls(for: snapshot.state)
    }

    func finish(_ state: VOCRRunState) {
        currentState = state
        updateControls(for: state)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let title = NSTextField(labelWithString: "Apple Vision OCR")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "선택한 PDF에 대해 필요한 출력만 생성합니다.")
        subtitle.textColor = .secondaryLabelColor

        let fileHeader = NSTextField(labelWithString: "선택 파일")
        fileHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        fileListField.textColor = .secondaryLabelColor

        let outputHeader = NSTextField(labelWithString: "출력 방식")
        outputHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        textCheckbox.target = self
        textCheckbox.action = #selector(outputCheckboxChanged)
        pageBreakCheckbox.target = self
        pageBreakCheckbox.action = #selector(outputCheckboxChanged)
        pdfCheckbox.target = self
        pdfCheckbox.action = #selector(outputCheckboxChanged)
        pdfCheckbox.state = .on

        let pageBreakStack = NSStackView(views: [spacer(width: 18), pageBreakCheckbox])
        pageBreakStack.orientation = .horizontal
        pageBreakStack.spacing = 0

        let outputStack = NSStackView(views: [textCheckbox, pageBreakStack, pdfCheckbox])
        outputStack.orientation = .vertical
        outputStack.alignment = .leading
        outputStack.spacing = 8

        let parallelismHeader = NSTextField(labelWithString: "동시 워커 프로세스 수")
        parallelismHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let recognitionLevelHeader = NSTextField(labelWithString: "인식 모드")
        recognitionLevelHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        recognitionLevelPopup.addItems(withTitles: ["정확도 우선", "속도 우선 (영문 전용)"])
        recognitionLevelPopup.selectItem(at: 0)
        let renderScaleHeader = NSTextField(labelWithString: "한국어 속도/품질")
        renderScaleHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        renderScalePopup.addItems(withTitles: ["품질 우선 (2.0x)", "한국어 속도 균형 (1.5x)", "빠른 초안 (1.25x)"])
        renderScalePopup.selectItem(at: 0)

        let recognitionLevelStack = NSStackView(views: [recognitionLevelHeader, recognitionLevelPopup])
        recognitionLevelStack.orientation = .horizontal
        recognitionLevelStack.alignment = .centerY
        recognitionLevelStack.spacing = 8
        let renderScaleStack = NSStackView(views: [renderScaleHeader, renderScalePopup])
        renderScaleStack.orientation = .horizontal
        renderScaleStack.alignment = .centerY
        renderScaleStack.spacing = 8

        parallelismStepper.minValue = Double(OCRJobParallelism.minimumCount)
        parallelismStepper.maxValue = Double(OCRJobParallelism.maximumCount)
        parallelismStepper.integerValue = Self.defaultWorkerCount
        parallelismStepper.target = self
        parallelismStepper.action = #selector(parallelismChanged)
        parallelismValueField.alignment = .center
        parallelismValueField.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let parallelismStack = NSStackView(views: [parallelismHeader, parallelismValueField, parallelismStepper])
        parallelismStack.orientation = .horizontal
        parallelismStack.alignment = .centerY
        parallelismStack.spacing = 8
        runInBackgroundCheckbox.state = .on

        outputPreviewField.textColor = .secondaryLabelColor

        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.isIndeterminate = false

        logView.isEditable = false
        logView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.documentView = logView
        logScroll.borderType = .bezelBorder
        logScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        startButton.target = self
        startButton.action = #selector(startClicked)
        startButton.keyEquivalent = "\r"
        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked)
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        quitButton.target = self
        quitButton.action = #selector(quitClicked)

        let buttonStack = NSStackView(views: [startButton, pauseButton, cancelButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let contentStack = NSStackView(views: [
            title,
            subtitle,
            separator(),
            fileHeader,
            fileListField,
            separator(),
            outputHeader,
            outputStack,
            outputPreviewField,
            recognitionLevelStack,
            renderScaleStack,
            parallelismStack,
            runInBackgroundCheckbox,
            separator(),
            progressIndicator,
            progressLabel,
            logScroll,
            buttonStack
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            progressIndicator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }

    private func updateFileList() {
        if files.isEmpty {
            fileListField.stringValue = "PDF 파일이 전달되지 않았습니다."
        } else {
            fileListField.stringValue = files.map(\.path).joined(separator: "\n")
        }
    }

    private func updateControls(for state: VOCRRunState) {
        let isRunning = state == .running
        let isPaused = state == .paused
        let isBusy = isRunning || isPaused

        startButton.isEnabled = !isBusy && !files.isEmpty && hasAnyOutputSelected
        pauseButton.isEnabled = isBusy
        pauseButton.title = isPaused ? "이어서 진행" : "일시정지"
        cancelButton.isEnabled = isBusy
        quitButton.isEnabled = !isBusy
        textCheckbox.isEnabled = !isBusy
        pageBreakCheckbox.isEnabled = !isBusy && textCheckbox.state == .on
        pdfCheckbox.isEnabled = !isBusy
        recognitionLevelPopup.isEnabled = !isBusy
        renderScalePopup.isEnabled = !isBusy
        parallelismStepper.isEnabled = !files.isEmpty
        runInBackgroundCheckbox.isEnabled = !isBusy
    }

    private func updateOutputControls() {
        if textCheckbox.state != .on {
            pageBreakCheckbox.state = .off
        }
        pageBreakCheckbox.isEnabled = currentState != .running && currentState != .paused && textCheckbox.state == .on
        outputPreviewField.stringValue = outputPreviewText()
        updateControls(for: currentState)
    }

    private var hasAnyOutputSelected: Bool {
        textCheckbox.state == .on || pdfCheckbox.state == .on
    }

    private func outputSelection() throws -> OCRJobOutputSelection {
        try OCRJobOutputSelection(
            writesText: textCheckbox.state == .on,
            writesPDF: pdfCheckbox.state == .on,
            includesPageBreaks: pageBreakCheckbox.state == .on
        )
    }

    private func parallelism() throws -> OCRJobParallelism {
        try OCRJobParallelism(count: parallelismStepper.integerValue)
    }

    private func recognitionLevel() -> OCRRecognitionLevel {
        recognitionLevelPopup.indexOfSelectedItem == 1 ? .fast : .accurate
    }

    private func renderScale() -> OCRRenderScale {
        switch renderScalePopup.indexOfSelectedItem {
        case 1:
            return .balanced
        case 2:
            return .compact
        default:
            return .quality
        }
    }

    private func outputPreviewText() -> String {
        guard hasAnyOutputSelected else {
            return "TXT 추출 또는 Searchable PDF 생성 중 하나 이상을 선택하세요."
        }

        var outputs: [String] = []
        if textCheckbox.state == .on {
            outputs.append("input.txt")
        }
        if pdfCheckbox.state == .on {
            outputs.append("input_ocr.pdf")
        }

        var text = "생성 파일: \(outputs.joined(separator: ", "))"
        if pageBreakCheckbox.state == .on {
            text += " · 구분자: ===== Page N ====="
        }
        return text
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func spacer(width: CGFloat) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    @objc private func outputCheckboxChanged() {
        updateOutputControls()
    }

    @objc private func parallelismChanged() {
        parallelismValueField.stringValue = "\(parallelismStepper.integerValue)"
        guard currentState == .running || currentState == .paused else {
            return
        }
        do {
            onParallelismChange(try parallelism())
        } catch {
            appendLog(error.localizedDescription)
        }
    }

    @objc private func startClicked() {
        do {
            let selection = try outputSelection()
            let parallelism = try parallelism()
            let recognitionLevel = recognitionLevel()
            let renderScale = renderScale()
            let shouldRunInBackground = runInBackgroundCheckbox.state == .on
            if recognitionLevel == .fast {
                recognitionLevelPopup.selectItem(at: 0)
                appendLog("속도 우선은 현재 Apple Vision에서 한국어 인식을 지원하지 않습니다. 정확도 우선으로 실행하세요.")
                return
            }
            guard confirmExistingSearchableTextIfNeeded(selection: selection) else {
                return
            }
            appendLog("작업 시작: \(recognitionLevel.rawValue) · 렌더 \(renderScale.value)x · 동시 워커 프로세스 \(parallelism.count)개")
            if shouldRunInBackground {
                window?.orderOut(nil)
            }
            onStart(selection, parallelism, recognitionLevel, renderScale, shouldRunInBackground)
        } catch OCRJobOptionError.missingOutput {
            appendLog("TXT 추출 또는 Searchable PDF 생성 중 하나 이상을 선택하세요.")
        } catch OCRJobOptionError.pageBreaksRequireText {
            appendLog("Page 구분자는 TXT 추출을 선택해야 사용할 수 있습니다.")
        } catch OCRJobOptionError.invalidParallelism {
            appendLog("동시 워커 프로세스 수는 \(OCRJobParallelism.minimumCount)-\(OCRJobParallelism.maximumCount) 사이여야 합니다.")
        } catch {
            appendLog(error.localizedDescription)
        }
    }

    @objc private func pauseClicked() {
        if currentState == .paused {
            onResume()
        } else {
            onPause()
        }
    }

    @objc private func cancelClicked() {
        onCancel()
    }

    @objc private func quitClicked() {
        onQuit()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func confirmExistingSearchableTextIfNeeded(selection: OCRJobOutputSelection) -> Bool {
        guard selection.writesPDF else {
            return true
        }

        let reports = files.compactMap { file -> (URL, PDFTextPresenceReport)? in
            do {
                let report = try textPresenceDetector.inspect(file)
                return report.hasText ? (file, report) : nil
            } catch {
                appendLog("기존 텍스트 검사 실패: \(file.lastPathComponent) · \(error.localizedDescription)")
                return nil
            }
        }
        guard !reports.isEmpty else {
            return true
        }

        let detail = reports.prefix(6).map { file, report in
            "\(file.lastPathComponent): \(report.textPageNumbers.count) page(s)"
        }.joined(separator: "\n")
        let omittedCount = reports.count - min(reports.count, 6)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "이미 선택 가능한 텍스트가 있는 PDF가 있습니다."
        alert.informativeText = """
        계속 진행하면 해당 페이지를 이미지로 평탄화한 뒤 새 OCR 텍스트만 다시 얹습니다.
        이렇게 하면 기존 searchable 텍스트가 중복 선택되는 문제를 피할 수 있습니다. 원본 PDF는 변경하지 않습니다.

        \(detail)\(omittedCount > 0 ? "\n외 \(omittedCount)개 파일" : "")
        """
        alert.addButton(withTitle: "계속 진행")
        alert.addButton(withTitle: "취소")

        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose()
    }
}
