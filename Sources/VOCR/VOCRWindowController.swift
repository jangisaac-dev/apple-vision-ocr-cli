import AppKit
import AppleVisionOCRCore

final class VOCRWindowController: NSWindowController, NSWindowDelegate {
    static var defaultWorkerCount: Int {
        min(OCRJobParallelism.maximumCount, max(2, ProcessInfo.processInfo.activeProcessorCount * 2 / 3))
    }

    var onStart: (OCRJobOutputSelection, OCRJobParallelism, OCRRecognitionLevel, OCRRenderScale, Bool, Bool) -> Void = { _, _, _, _, _, _ in }
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onCancel: () -> Void = {}
    var onParallelismChange: (OCRJobParallelism) -> Void = { _ in }
    var onWindowWillClose: () -> Void = {}
    var onQuit: () -> Void = {}

    private let files: [URL]
    private var currentState: VOCRRunState = .idle
    private let textPresenceDetector = PDFTextPresenceDetector()

    private let fileListScroll = NSTextView.scrollableTextView()
    private var fileListView: NSTextView { fileListScroll.documentView as! NSTextView }
    private let outputPreviewField = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: VOCRStrings.statusReady.text)
    private let logView = NSTextView()
    private let textCheckbox = NSButton(checkboxWithTitle: VOCRStrings.checkboxExtractText.text, target: nil, action: nil)
    private let pageBreakCheckbox = NSButton(checkboxWithTitle: VOCRStrings.checkboxInsertPageSeparators.text, target: nil, action: nil)
    private let pdfCheckbox = NSButton(checkboxWithTitle: VOCRStrings.checkboxGenerateSearchablePDF.text, target: nil, action: nil)
    private let recognitionLevelPopup = NSPopUpButton()
    private let renderScalePopup = NSPopUpButton()
    private let disableLanguageCorrectionCheckbox = NSButton(checkboxWithTitle: VOCRStrings.checkboxDisableLanguageCorrection.text, target: nil, action: nil)
    private let parallelismStepper = NSStepper()
    private let parallelismValueField = NSTextField(labelWithString: "\(VOCRWindowController.defaultWorkerCount)")
    private let runInBackgroundCheckbox = NSButton(checkboxWithTitle: VOCRStrings.checkboxRunInBackground.text, target: nil, action: nil)
    private let startButton = NSButton(title: VOCRStrings.buttonStart.text, target: nil, action: nil)
    private let pauseButton = NSButton(title: VOCRStrings.buttonPause.text, target: nil, action: nil)
    private let cancelButton = NSButton(title: VOCRStrings.buttonCancel.text, target: nil, action: nil)
    private let quitButton = NSButton(title: VOCRStrings.buttonQuit.text, target: nil, action: nil)

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
        var lines = [VOCRStrings.logPlannedOutput(output.inputURL.lastPathComponent)]
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

        let subtitle = NSTextField(labelWithString: VOCRStrings.labelSubtitle.text)
        subtitle.textColor = .secondaryLabelColor

        let fileHeader = NSTextField(labelWithString: VOCRStrings.headerSelectedFiles.text)
        fileHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        fileListView.isEditable = false
        fileListView.textColor = .secondaryLabelColor
        // 긴 경로는 줄바꿈 대신 가로 스크롤
        fileListView.isHorizontallyResizable = true
        fileListView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        fileListView.textContainer?.widthTracksTextView = false
        fileListView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        fileListScroll.hasHorizontalScroller = true
        fileListScroll.borderType = .bezelBorder
        fileListScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true

        let outputHeader = NSTextField(labelWithString: VOCRStrings.headerOutputOptions.text)
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

        let parallelismHeader = NSTextField(labelWithString: VOCRStrings.headerWorkerProcessCount.text)
        parallelismHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let recognitionLevelHeader = NSTextField(labelWithString: VOCRStrings.headerRecognitionMode.text)
        recognitionLevelHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        recognitionLevelPopup.addItems(withTitles: [
            VOCRStrings.popupRecognitionAccuracyFirst.text,
            VOCRStrings.popupRecognitionSpeedFirst.text
        ])
        recognitionLevelPopup.selectItem(at: 0)
        let renderScaleHeader = NSTextField(labelWithString: VOCRStrings.headerRenderScale.text)
        renderScaleHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        renderScalePopup.addItems(withTitles: [
            VOCRStrings.popupRenderScaleQuality.text,
            VOCRStrings.popupRenderScaleBalanced.text,
            VOCRStrings.popupRenderScaleFastDraft.text
        ])
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
            fileListScroll,
            separator(),
            outputHeader,
            outputStack,
            outputPreviewField,
            recognitionLevelStack,
            renderScaleStack,
            disableLanguageCorrectionCheckbox,
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
            logScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fileListScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }

    private func updateFileList() {
        if files.isEmpty {
            fileListView.string = VOCRStrings.placeholderNoPDFFiles.text
        } else {
            fileListView.string = files.map(\.path).joined(separator: "\n")
        }
        fileListView.scrollToBeginningOfDocument(nil)
    }

    private func updateControls(for state: VOCRRunState) {
        let isRunning = state == .running
        let isPaused = state == .paused
        let isBusy = isRunning || isPaused

        startButton.isEnabled = !isBusy && !files.isEmpty && hasAnyOutputSelected
        pauseButton.isEnabled = isBusy
        pauseButton.title = isPaused ? VOCRStrings.buttonResume.text : VOCRStrings.buttonPause.text
        cancelButton.isEnabled = isBusy
        quitButton.isEnabled = !isBusy
        textCheckbox.isEnabled = !isBusy
        pageBreakCheckbox.isEnabled = !isBusy && textCheckbox.state == .on
        pdfCheckbox.isEnabled = !isBusy
        recognitionLevelPopup.isEnabled = !isBusy
        renderScalePopup.isEnabled = !isBusy
        disableLanguageCorrectionCheckbox.isEnabled = !isBusy
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
            return VOCRStrings.validationMissingOutput.text
        }

        var outputs: [String] = []
        if textCheckbox.state == .on {
            outputs.append("input.txt")
        }
        if pdfCheckbox.state == .on {
            outputs.append("input_ocr.pdf")
        }

        var text = VOCRStrings.previewGeneratedFiles(outputs.joined(separator: ", "))
        if pageBreakCheckbox.state == .on {
            text += VOCRStrings.previewPageSeparator.text
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
            let usesLanguageCorrection = disableLanguageCorrectionCheckbox.state != .on
            let shouldRunInBackground = runInBackgroundCheckbox.state == .on
            if recognitionLevel == .fast {
                recognitionLevelPopup.selectItem(at: 0)
                appendLog(VOCRStrings.logSpeedFirstKoreanUnsupported.text)
                return
            }
            guard confirmExistingSearchableTextIfNeeded(selection: selection) else {
                return
            }
            appendLog(VOCRStrings.logJobStartedWithOptions(
                recognitionLevel: recognitionLevel.rawValue,
                renderScale: renderScale.value,
                workerCount: parallelism.count
            ))
            if shouldRunInBackground {
                window?.orderOut(nil)
            }
            onStart(selection, parallelism, recognitionLevel, renderScale, usesLanguageCorrection, shouldRunInBackground)
        } catch OCRJobOptionError.missingOutput {
            appendLog(VOCRStrings.validationMissingOutput.text)
        } catch OCRJobOptionError.pageBreaksRequireText {
            appendLog(VOCRStrings.logPageBreaksRequireText.text)
        } catch OCRJobOptionError.invalidParallelism {
            appendLog(VOCRStrings.logInvalidParallelism(
                minimumCount: OCRJobParallelism.minimumCount,
                maximumCount: OCRJobParallelism.maximumCount
            ))
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
                appendLog(VOCRStrings.logExistingTextInspectionFailed(
                    fileName: file.lastPathComponent,
                    errorDescription: error.localizedDescription
                ))
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
        alert.messageText = VOCRStrings.alertExistingTextMessage.text
        alert.informativeText = VOCRStrings.alertExistingTextBody(
            detail: detail,
            omittedCount: omittedCount
        )
        alert.addButton(withTitle: VOCRStrings.buttonContinue.text)
        alert.addButton(withTitle: VOCRStrings.buttonCancel.text)

        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose()
    }
}
