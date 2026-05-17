# VOCR Finder GUI And Menubar Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Finder-launched `VOCR.app` that shows one `Apple Vision OCR` Quick Action, offers TXT/PDF/page-divided options in a detail window, and reports OCR progress through a menu bar item with pause, resume, and cancel controls.

**Architecture:** Split the current executable-only Swift package into a reusable `AppleVisionOCRCore` library plus two executables: the existing `apple-vision-ocr` CLI and a new AppKit `VOCR` GUI executable packaged as `VOCR.app`. The OCR core owns page counting, Vision OCR, PDF/TXT output, unique GUI output paths, progress callbacks, and page-boundary pause/cancel checks; the GUI owns option selection, detail window state, menu bar progress, and Finder integration.

**Tech Stack:** SwiftPM, Swift 5.9, AppKit, CoreGraphics, CoreText, Vision, Foundation, XCTest, Automator Quick Action shell wrapper.

---

## File Structure

Create or modify these files.

- Modify `Package.swift`: add `AppleVisionOCRCore` library target, keep `apple-vision-ocr` executable, add `VOCR` executable, point tests at the core library.
- Move existing core files from `Sources/AppleVisionOCRCLI/` to `Sources/AppleVisionOCRCore/` except `main.swift` and `CommandRunner.swift`.
- Create `Sources/AppleVisionOCRCLI/CommandRunner.swift` as CLI-only wrapper importing `AppleVisionOCRCore`.
- Create `Sources/AppleVisionOCRCLI/main.swift` as CLI entrypoint importing `AppleVisionOCRCore`.
- Create `Sources/AppleVisionOCRCore/OCRJobOptions.swift`: shared output-mode and job option types.
- Create `Sources/AppleVisionOCRCore/OCRProgress.swift`: progress event, stage, cancellation, and pause state types.
- Create `Sources/AppleVisionOCRCore/UniqueOutputPathResolver.swift`: GUI-safe sibling output path generation.
- Modify `Sources/AppleVisionOCRCore/SearchablePDFPipeline.swift`: report structured progress, honor pause/cancel at page boundaries, support atomic output writes.
- Modify `Sources/AppleVisionOCRCore/TextOutputWriter.swift`: keep `===== Page N =====` page divider behavior.
- Create `Sources/VOCR/main.swift`: AppKit application entrypoint.
- Create `Sources/VOCR/VOCRAppDelegate.swift`: application lifecycle, argument parsing, window creation.
- Create `Sources/VOCR/VOCRWindowController.swift`: detail window UI and option controls.
- Create `Sources/VOCR/OCRJobController.swift`: runs OCR job off the main thread and bridges progress to UI.
- Create `Sources/VOCR/StatusItemController.swift`: `NSStatusItem`, percent title, right-click menu, pause/resume/cancel menu actions.
- Create `Sources/VOCR/ProgressStore.swift`: JSON progress file writing under `~/Library/Application Support/VOCR/progress/`.
- Create `Tests/AppleVisionOCRCoreTests/OutputModeTests.swift`.
- Create `Tests/AppleVisionOCRCoreTests/UniqueOutputPathResolverTests.swift`.
- Create `Tests/AppleVisionOCRCoreTests/OCRProgressStateTests.swift`.
- Move current tests from `Tests/AppleVisionOCRCLITests/` to `Tests/AppleVisionOCRCoreTests/` where they test core behavior.
- Keep or create `Tests/AppleVisionOCRCLITests/CLIOptionsTests.swift` for CLI parse behavior.
- Create `scripts/package-vocr-app.sh`: builds release binaries and creates `VOCR.app`.
- Create `scripts/install-vocr-quick-action.sh`: installs `VOCR.app`, CLI binary, wrapper, and the single Finder Quick Action.
- Create `scripts/vocr-finder-action.sh`: thin Finder wrapper that launches `VOCR.app` with selected PDFs.
- Modify `README.md`: document the GUI, menu bar controls, and install script.

## Task 1: Split Swift Package Into Core Library, CLI, And VOCR Executable

**Files:**
- Modify: `Package.swift`
- Move: `Sources/AppleVisionOCRCLI/*.swift` to `Sources/AppleVisionOCRCore/` except `main.swift` and `CommandRunner.swift`
- Modify: `Sources/AppleVisionOCRCLI/CommandRunner.swift`
- Modify: `Sources/AppleVisionOCRCLI/main.swift`
- Move tests as needed under `Tests/AppleVisionOCRCoreTests/`

- [ ] **Step 1: Write the package structure test by running current tests first**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
```

Expected before the package split: PASS with the existing test count. If sandbox blocks SwiftPM manifest loading, rerun the same command with escalated permissions.

- [ ] **Step 2: Replace `Package.swift` with the multi-target layout**

Use this package definition:

```swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "apple-vision-ocr-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppleVisionOCRCore", targets: ["AppleVisionOCRCore"]),
        .executable(name: "apple-vision-ocr", targets: ["AppleVisionOCRCLI"]),
        .executable(name: "VOCR", targets: ["VOCR"])
    ],
    targets: [
        .target(name: "AppleVisionOCRCore"),
        .executableTarget(
            name: "AppleVisionOCRCLI",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .executableTarget(
            name: "VOCR",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .testTarget(
            name: "AppleVisionOCRCoreTests",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .testTarget(
            name: "AppleVisionOCRCLITests",
            dependencies: ["AppleVisionOCRCLI", "AppleVisionOCRCore"]
        )
    ]
)
```

- [ ] **Step 3: Move core files**

Create `Sources/AppleVisionOCRCore/` and move these files into it:

```text
CLIOptions.swift
Errors.swift
GeometryMapper.swift
LanguageParser.swift
OCRRecognitionLevel.swift
OutputPathResolver.swift
PDFRenderer.swift
PDFTextOverlayWriter.swift
SearchablePDFPipeline.swift
TextOutputWriter.swift
VisionLanguageResolver.swift
VisionTextRecognizer.swift
```

Leave these files under `Sources/AppleVisionOCRCLI/`:

```text
CommandRunner.swift
main.swift
```

- [ ] **Step 4: Update CLI imports**

At the top of `Sources/AppleVisionOCRCLI/CommandRunner.swift`, add:

```swift
import AppleVisionOCRCore
```

At the top of `Sources/AppleVisionOCRCLI/main.swift`, add:

```swift
import AppleVisionOCRCore
```

- [ ] **Step 5: Update test imports**

For tests that exercise core types, change:

```swift
@testable import AppleVisionOCRCLI
```

to:

```swift
@testable import AppleVisionOCRCore
```

For CLI parser tests that need `CommandRunner`, keep:

```swift
@testable import AppleVisionOCRCLI
@testable import AppleVisionOCRCore
```

- [ ] **Step 6: Run tests and fix access control**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
```

Expected: initial failures may mention inaccessible types after moving to `AppleVisionOCRCore`. Fix by making shared core types `public` only where they are consumed by `AppleVisionOCRCLI` or `VOCR`. Keep implementation-only helpers `internal`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Split OCR core from CLI" \
  -m "Intent: Prepare the Swift package for a shared CLI and VOCR GUI implementation." \
  -m "Context: The Apple Vision OCR pipeline now lives in AppleVisionOCRCore so the CLI and Finder-launched app can share OCR, output, and progress behavior." \
  -m "Constraint: No GUI behavior is added in this commit; this is a package boundary change only." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 2: Add Shared Output Mode, Unique Output Paths, And Progress Types

**Files:**
- Create: `Sources/AppleVisionOCRCore/OCRJobOptions.swift`
- Create: `Sources/AppleVisionOCRCore/OCRProgress.swift`
- Create: `Sources/AppleVisionOCRCore/UniqueOutputPathResolver.swift`
- Test: `Tests/AppleVisionOCRCoreTests/OutputModeTests.swift`
- Test: `Tests/AppleVisionOCRCoreTests/UniqueOutputPathResolverTests.swift`
- Test: `Tests/AppleVisionOCRCoreTests/OCRProgressStateTests.swift`

- [ ] **Step 1: Write output mode tests**

Create `Tests/AppleVisionOCRCoreTests/OutputModeTests.swift`:

```swift
import XCTest
@testable import AppleVisionOCRCore

final class OutputModeTests: XCTestCase {
    func testRequiresAtLeastOneOutput() {
        XCTAssertThrowsError(try OCRJobOutputMode(writesPDF: false, writesText: false, includesPageBreaks: false)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .missingOutput)
        }
    }

    func testPageBreaksRequireTextOutput() {
        XCTAssertThrowsError(try OCRJobOutputMode(writesPDF: true, writesText: false, includesPageBreaks: true)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .pageBreaksRequireText)
        }
    }

    func testAllowsPageDividedTextOnly() throws {
        let mode = try OCRJobOutputMode(writesPDF: false, writesText: true, includesPageBreaks: true)

        XCTAssertFalse(mode.writesPDF)
        XCTAssertTrue(mode.writesText)
        XCTAssertTrue(mode.includesPageBreaks)
    }
}
```

- [ ] **Step 2: Verify output mode tests fail**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter OutputModeTests
```

Expected: FAIL because `OCRJobOutputMode` and `OCRJobOptionError` do not exist.

- [ ] **Step 3: Implement output mode types**

Create `Sources/AppleVisionOCRCore/OCRJobOptions.swift`:

```swift
import Foundation

public enum OCRJobOptionError: Error, Equatable {
    case missingOutput
    case pageBreaksRequireText
}

public struct OCRJobOutputMode: Equatable {
    public let writesPDF: Bool
    public let writesText: Bool
    public let includesPageBreaks: Bool

    public init(writesPDF: Bool, writesText: Bool, includesPageBreaks: Bool) throws {
        guard writesPDF || writesText else {
            throw OCRJobOptionError.missingOutput
        }
        guard writesText || !includesPageBreaks else {
            throw OCRJobOptionError.pageBreaksRequireText
        }

        self.writesPDF = writesPDF
        self.writesText = writesText
        self.includesPageBreaks = includesPageBreaks
    }
}

public struct OCRJobInput: Equatable {
    public let inputURL: URL
    public let pdfOutputURL: URL?
    public let textOutputURL: URL?

    public init(inputURL: URL, pdfOutputURL: URL?, textOutputURL: URL?) {
        self.inputURL = inputURL
        self.pdfOutputURL = pdfOutputURL
        self.textOutputURL = textOutputURL
    }
}
```

- [ ] **Step 4: Write unique output path tests**

Create `Tests/AppleVisionOCRCoreTests/UniqueOutputPathResolverTests.swift`:

```swift
import XCTest
@testable import AppleVisionOCRCore

final class UniqueOutputPathResolverTests: XCTestCase {
    func testReturnsDefaultPDFPathWhenAvailable() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())

        let output = try UniqueOutputPathResolver.availablePDFOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample_ocr.pdf")
    }

    func testReturnsNumberedPDFPathWhenDefaultExists() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        let existing = directory.appendingPathComponent("sample_ocr.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let output = try UniqueOutputPathResolver.availablePDFOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample_ocr(1).pdf")
    }

    func testReturnsNumberedTextPathWhenDefaultExists() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        let existing = directory.appendingPathComponent("sample.txt")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let output = try UniqueOutputPathResolver.availableTextOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample(1).txt")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
```

- [ ] **Step 5: Verify unique output path tests fail**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter UniqueOutputPathResolverTests
```

Expected: FAIL because `UniqueOutputPathResolver` does not exist.

- [ ] **Step 6: Implement unique output path resolver**

Create `Sources/AppleVisionOCRCore/UniqueOutputPathResolver.swift`:

```swift
import Foundation

public enum UniqueOutputPathResolver {
    public static func availablePDFOutputURL(for inputURL: URL, fileManager: FileManager = .default) throws -> URL {
        let defaultURL = try OutputPathResolver.defaultOutputURL(for: inputURL)
        return availableURL(defaultURL, fileManager: fileManager)
    }

    public static func availableTextOutputURL(for inputURL: URL, fileManager: FileManager = .default) throws -> URL {
        let defaultURL = try OutputPathResolver.defaultTextOutputURL(for: inputURL)
        return availableURL(defaultURL, fileManager: fileManager)
    }

    private static func availableURL(_ defaultURL: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: defaultURL.path) else {
            return defaultURL
        }

        let directory = defaultURL.deletingLastPathComponent()
        let baseName = defaultURL.deletingPathExtension().lastPathComponent
        let pathExtension = defaultURL.pathExtension

        var counter = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)(\(counter))")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
```

- [ ] **Step 7: Write progress state tests**

Create `Tests/AppleVisionOCRCoreTests/OCRProgressStateTests.swift`:

```swift
import XCTest
@testable import AppleVisionOCRCore

final class OCRProgressStateTests: XCTestCase {
    func testPercentUsesCompletedPagesOverTotalPages() {
        let event = OCRProgressEvent(
            stage: .recognizingText,
            currentFile: "sample.pdf",
            completedPages: 2,
            totalPages: 5,
            message: "OCR page 2/5"
        )

        XCTAssertEqual(event.percent, 40)
    }

    func testZeroTotalPagesReportsZeroPercent() {
        let event = OCRProgressEvent(
            stage: .starting,
            currentFile: nil,
            completedPages: 0,
            totalPages: 0,
            message: "Starting"
        )

        XCTAssertEqual(event.percent, 0)
    }
}
```

- [ ] **Step 8: Verify progress tests fail**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter OCRProgressStateTests
```

Expected: FAIL because `OCRProgressEvent` does not exist.

- [ ] **Step 9: Implement progress types**

Create `Sources/AppleVisionOCRCore/OCRProgress.swift`:

```swift
import Foundation

public enum OCRProgressStage: String, Codable, Equatable {
    case starting
    case countingPages
    case renderingPage
    case recognizingText
    case writingOutput
    case paused
    case canceled
    case completed
    case failed
}

public struct OCRProgressEvent: Codable, Equatable {
    public let stage: OCRProgressStage
    public let currentFile: String?
    public let completedPages: Int
    public let totalPages: Int
    public let message: String

    public var percent: Int {
        guard totalPages > 0 else {
            return 0
        }
        return min(100, max(0, Int((Double(completedPages) / Double(totalPages) * 100).rounded(.down))))
    }

    public init(stage: OCRProgressStage, currentFile: String?, completedPages: Int, totalPages: Int, message: String) {
        self.stage = stage
        self.currentFile = currentFile
        self.completedPages = completedPages
        self.totalPages = totalPages
        self.message = message
    }
}

public final class OCRJobControl {
    private let lock = NSLock()
    private var paused = false
    private var canceled = false

    public init() {}

    public func pause() {
        lock.withLock {
            paused = true
        }
    }

    public func resume() {
        lock.withLock {
            paused = false
        }
    }

    public func cancel() {
        lock.withLock {
            canceled = true
            paused = false
        }
    }

    public var isPaused: Bool {
        lock.withLock {
            paused
        }
    }

    public var isCanceled: Bool {
        lock.withLock {
            canceled
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
```

- [ ] **Step 10: Run core tests**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter AppleVisionOCRCoreTests
```

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add Sources/AppleVisionOCRCore Tests/AppleVisionOCRCoreTests
git commit -m "Add VOCR job mode and progress models" \
  -m "Intent: Add shared output mode, unique path, and structured progress primitives for the VOCR GUI." \
  -m "Context: Finder GUI output handling needs safe sibling filenames and page-based progress independent of Automator gear progress." \
  -m "Constraint: This commit does not add AppKit UI or Finder installation behavior." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter AppleVisionOCRCoreTests." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 3: Extend OCR Pipeline For Structured Progress, Pause, Cancel, And Atomic Outputs

**Files:**
- Modify: `Sources/AppleVisionOCRCore/SearchablePDFPipeline.swift`
- Modify: `Sources/AppleVisionOCRCore/TextOutputWriter.swift`
- Create: `Tests/AppleVisionOCRCoreTests/TextOutputWriterPageBreakTests.swift`
- Create: `Tests/AppleVisionOCRCoreTests/OCRJobControlTests.swift`

- [ ] **Step 1: Preserve exact page divider tests**

Create `Tests/AppleVisionOCRCoreTests/TextOutputWriterPageBreakTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import AppleVisionOCRCore

final class TextOutputWriterPageBreakTests: XCTestCase {
    func testPageDividerMatchesOwlOCRWorkflowFormat() {
        let writer = TextOutputWriter()
        let output = writer.render(
            pages: [
                page(1, texts: ["First"]),
                page(2, texts: ["Second"])
            ],
            includePageBreaks: true
        )

        XCTAssertEqual(output, "===== Page 1 =====\n\nFirst\n\n===== Page 2 =====\n\nSecond\n")
    }

    func testPlainTextDoesNotIncludePageDivider() {
        let writer = TextOutputWriter()
        let output = writer.render(
            pages: [
                page(1, texts: ["First"]),
                page(2, texts: ["Second"])
            ],
            includePageBreaks: false
        )

        XCTAssertEqual(output, "First\n\nSecond\n")
    }

    private func page(_ pageNumber: Int, texts: [String]) -> PDFPageOCRResult {
        PDFPageOCRResult(
            pageNumber: pageNumber,
            geometry: PDFPageGeometry(mediaBox: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 0),
            overlays: texts.map { PDFTextOverlay(text: $0, rect: .zero) }
        )
    }
}
```

- [ ] **Step 2: Run page divider tests**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --filter TextOutputWriterPageBreakTests
```

Expected: PASS if current text writer already matches, otherwise FAIL showing the exact string mismatch.

- [ ] **Step 3: Add control tests**

Create `Tests/AppleVisionOCRCoreTests/OCRJobControlTests.swift`:

```swift
import XCTest
@testable import AppleVisionOCRCore

final class OCRJobControlTests: XCTestCase {
    func testPauseResumeCancelFlags() {
        let control = OCRJobControl()

        XCTAssertFalse(control.isPaused)
        XCTAssertFalse(control.isCanceled)

        control.pause()
        XCTAssertTrue(control.isPaused)
        XCTAssertFalse(control.isCanceled)

        control.resume()
        XCTAssertFalse(control.isPaused)

        control.cancel()
        XCTAssertFalse(control.isPaused)
        XCTAssertTrue(control.isCanceled)
    }
}
```

- [ ] **Step 4: Modify pipeline API**

Change `SearchablePDFPipeline.run` signature to:

```swift
public func run(
    options: CLIOptions,
    control: OCRJobControl = OCRJobControl(),
    progress: (OCRProgressEvent) -> Void = { _ in }
) throws
```

Keep the CLI convenience by adapting `CommandRunner` to print `event.message` to stderr.

- [ ] **Step 5: Add page-boundary pause/cancel checks**

Inside the page loop in `SearchablePDFPipeline.run`, before rendering each page, add:

```swift
while control.isPaused {
    progress(OCRProgressEvent(
        stage: .paused,
        currentFile: options.inputURL.lastPathComponent,
        completedPages: pageResults.count,
        totalPages: document.numberOfPages,
        message: "Paused"
    ))
    Thread.sleep(forTimeInterval: 0.2)
}

if control.isCanceled {
    throw AppleVisionOCRError.pdfFailure("OCR canceled")
}
```

After appending each page result, emit:

```swift
progress(OCRProgressEvent(
    stage: .recognizingText,
    currentFile: options.inputURL.lastPathComponent,
    completedPages: pageResults.count,
    totalPages: document.numberOfPages,
    message: "OCR page \(pageResults.count)/\(document.numberOfPages)"
))
```

- [ ] **Step 6: Add output writing progress**

Before writing outputs, emit:

```swift
progress(OCRProgressEvent(
    stage: .writingOutput,
    currentFile: options.inputURL.lastPathComponent,
    completedPages: document.numberOfPages,
    totalPages: document.numberOfPages,
    message: "Writing output"
))
```

After all outputs are written, emit:

```swift
progress(OCRProgressEvent(
    stage: .completed,
    currentFile: options.inputURL.lastPathComponent,
    completedPages: document.numberOfPages,
    totalPages: document.numberOfPages,
    message: "Completed"
))
```

- [ ] **Step 7: Update CLI progress printing**

In `CommandRunner.run`, replace the current string progress closure with:

```swift
try pipeline.run(options: options) { [stderr] event in
    stderr(event.message)
}
```

- [ ] **Step 8: Run all tests**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources Tests
git commit -m "Add structured OCR progress controls" \
  -m "Intent: Let the shared OCR pipeline report page progress and honor pause, resume, and cancel state at page boundaries." \
  -m "Context: VOCR.app needs reliable progress without relying on Automator gear progress or stderr parsing." \
  -m "Constraint: Vision requests are not interrupted mid-page; pause and cancel apply before starting the next page." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 4: Build VOCR Job Controller And Progress Store

**Files:**
- Create: `Sources/VOCR/OCRJobController.swift`
- Create: `Sources/VOCR/ProgressStore.swift`
- Create: `Sources/VOCR/VOCRJobState.swift`
- Test: `Tests/AppleVisionOCRCoreTests/ProgressStoreEncodingTests.swift`

- [ ] **Step 1: Write progress JSON encoding test in core tests**

Create `Tests/AppleVisionOCRCoreTests/ProgressStoreEncodingTests.swift` for the codable event shape:

```swift
import XCTest
@testable import AppleVisionOCRCore

final class ProgressStoreEncodingTests: XCTestCase {
    func testProgressEventEncodesStableJSONFields() throws {
        let event = OCRProgressEvent(
            stage: .recognizingText,
            currentFile: "sample.pdf",
            completedPages: 1,
            totalPages: 4,
            message: "OCR page 1/4"
        )

        let data = try JSONEncoder().encode(event)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["stage"] as? String, "recognizingText")
        XCTAssertEqual(object?["currentFile"] as? String, "sample.pdf")
        XCTAssertEqual(object?["completedPages"] as? Int, 1)
        XCTAssertEqual(object?["totalPages"] as? Int, 4)
        XCTAssertEqual(object?["message"] as? String, "OCR page 1/4")
    }
}
```

- [ ] **Step 2: Implement VOCR job state**

Create `Sources/VOCR/VOCRJobState.swift`:

```swift
import Foundation
import AppleVisionOCRCore

enum VOCRJobRunState: Equatable {
    case idle
    case running
    case paused
    case completed
    case failed(String)
    case canceled
}

struct VOCRJobState: Equatable {
    var runState: VOCRJobRunState
    var progress: OCRProgressEvent

    var menuTitle: String {
        switch runState {
        case .completed:
            return "VOCR 완료"
        case .failed:
            return "VOCR 실패"
        case .idle:
            return "VOCR"
        case .paused:
            return "VOCR \(progress.percent)%"
        case .running:
            return "VOCR \(progress.percent)%"
        case .canceled:
            return "VOCR 취소"
        }
    }
}
```

- [ ] **Step 3: Implement progress store**

Create `Sources/VOCR/ProgressStore.swift`:

```swift
import Foundation
import AppleVisionOCRCore

final class ProgressStore {
    private let directory: URL
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.directory = appSupport
            .appendingPathComponent("VOCR", isDirectory: true)
            .appendingPathComponent("progress", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func write(event: OCRProgressEvent, jobID: UUID) {
        let outputURL = directory.appendingPathComponent("\(jobID.uuidString).json")
        let temporaryURL = outputURL.appendingPathExtension("tmp")
        do {
            let data = try encoder.encode(event)
            try data.write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }
}
```

- [ ] **Step 4: Implement job controller**

Create `Sources/VOCR/OCRJobController.swift`:

```swift
import Foundation
import AppleVisionOCRCore

@MainActor
final class OCRJobController {
    private let pipeline: SearchablePDFPipeline
    private let progressStore: ProgressStore?
    private let control = OCRJobControl()
    private let jobID = UUID()
    private var task: Task<Void, Never>?

    var onProgress: ((VOCRJobState) -> Void)?
    var onComplete: (() -> Void)?

    init(pipeline: SearchablePDFPipeline = SearchablePDFPipeline()) {
        self.pipeline = pipeline
        self.progressStore = try? ProgressStore()
    }

    func start(options: CLIOptions) {
        task = Task.detached { [pipeline, control, progressStore, jobID] in
            do {
                try pipeline.run(options: options, control: control) { event in
                    progressStore?.write(event: event, jobID: jobID)
                    Task { @MainActor [weak self] in
                        self?.onProgress?(VOCRJobState(runState: control.isPaused ? .paused : .running, progress: event))
                    }
                }
                Task { @MainActor [weak self] in
                    self?.onComplete?()
                }
            } catch {
                let failedEvent = OCRProgressEvent(
                    stage: .failed,
                    currentFile: options.inputURL.lastPathComponent,
                    completedPages: 0,
                    totalPages: 0,
                    message: error.localizedDescription
                )
                Task { @MainActor [weak self] in
                    self?.onProgress?(VOCRJobState(runState: .failed(error.localizedDescription), progress: failedEvent))
                }
            }
        }
    }

    func pause() {
        control.pause()
    }

    func resume() {
        control.resume()
    }

    func cancel() {
        control.cancel()
    }
}
```

- [ ] **Step 5: Run build**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build
```

Expected: PASS after resolving actor isolation warnings by keeping UI callbacks on `MainActor`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VOCR Tests/AppleVisionOCRCoreTests
git commit -m "Add VOCR job controller" \
  -m "Intent: Add the GUI-side job state, progress persistence, and pause/resume/cancel bridge." \
  -m "Context: The menu bar and detail window need a stable state model fed by structured OCR progress events." \
  -m "Constraint: The job controller owns UI bridging only; OCR behavior remains in AppleVisionOCRCore." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 5: Add VOCR Detail Window

**Files:**
- Create: `Sources/VOCR/main.swift`
- Create: `Sources/VOCR/VOCRAppDelegate.swift`
- Create: `Sources/VOCR/VOCRWindowController.swift`

- [ ] **Step 1: Create AppKit entrypoint**

Create `Sources/VOCR/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = VOCRAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

- [ ] **Step 2: Create app delegate**

Create `Sources/VOCR/VOCRAppDelegate.swift`:

```swift
import AppKit
import Foundation

final class VOCRAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: VOCRWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
        let controller = VOCRWindowController(inputURLs: urls)
        self.windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```

- [ ] **Step 3: Create window controller UI**

Create `Sources/VOCR/VOCRWindowController.swift` with programmatic AppKit controls:

```swift
import AppKit
import Foundation

final class VOCRWindowController: NSWindowController {
    private let inputURLs: [URL]
    private let textCheckbox = NSButton(checkboxWithTitle: "TXT 추출", target: nil, action: nil)
    private let pageBreaksCheckbox = NSButton(checkboxWithTitle: "페이지 구분 포함", target: nil, action: nil)
    private let pdfCheckbox = NSButton(checkboxWithTitle: "검색 가능한 PDF 생성", target: nil, action: nil)
    private let startButton = NSButton(title: "시작", target: nil, action: nil)
    private let cancelButton = NSButton(title: "취소", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "대기 중")

    init(inputURLs: [URL]) {
        self.inputURLs = inputURLs
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Apple Vision OCR"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        pdfCheckbox.state = .on
        pageBreaksCheckbox.isEnabled = false
        textCheckbox.target = self
        textCheckbox.action = #selector(textOptionChanged)
        startButton.target = self
        startButton.action = #selector(startPressed)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)

        let fileList = NSTextField(labelWithString: inputURLs.map(\.lastPathComponent).joined(separator: "\n"))
        fileList.lineBreakMode = .byTruncatingMiddle
        fileList.maximumNumberOfLines = 4

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "\(inputURLs.count)개 PDF 선택됨"),
            fileList,
            textCheckbox,
            pageBreaksCheckbox,
            pdfCheckbox,
            statusLabel,
            NSStackView(views: [startButton, cancelButton])
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        window?.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 20)
        ])
    }

    @objc private func textOptionChanged() {
        pageBreaksCheckbox.isEnabled = textCheckbox.state == .on
        if textCheckbox.state == .off {
            pageBreaksCheckbox.state = .off
        }
    }

    @objc private func startPressed() {
        statusLabel.stringValue = "시작 준비 완료"
    }

    @objc private func cancelPressed() {
        statusLabel.stringValue = "취소 요청됨"
    }
}
```

- [ ] **Step 4: Build VOCR executable**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR
```

Expected: PASS.

- [ ] **Step 5: Smoke run VOCR executable**

Run:

```bash
.build/debug/VOCR Samples/sample.pdf
```

Expected: a small `Apple Vision OCR` window appears with one selected file and default PDF option checked. Close the window manually. Then verify no leftover VOCR process:

```bash
ps -axo pid,comm,args | rg -i 'VOCR|apple-vision-ocr'
```

Expected: only the `ps` and `rg` commands are shown.

- [ ] **Step 6: Commit**

```bash
git add Sources/VOCR
git commit -m "Add VOCR detail window" \
  -m "Intent: Add the Finder-launched VOCR app window for selecting OCR output modes." \
  -m "Context: The Finder Quick Action will show one Apple Vision OCR entry and defer TXT/PDF/page-divided choices to this native window." \
  -m "Constraint: This commit builds the window shell only; full OCR execution and menu bar integration are wired in later tasks." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR; .build/debug/VOCR Samples/sample.pdf." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 6: Add Menu Bar Status Item With Right-Click Menu

**Files:**
- Create: `Sources/VOCR/StatusItemController.swift`
- Modify: `Sources/VOCR/VOCRWindowController.swift`

- [ ] **Step 1: Create status item controller**

Create `Sources/VOCR/StatusItemController.swift`:

```swift
import AppKit
import AppleVisionOCRCore

@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var pauseAction: (() -> Void)?
    private var resumeAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var showWindowAction: (() -> Void)?
    private var lastState = VOCRJobState(
        runState: .idle,
        progress: OCRProgressEvent(stage: .starting, currentFile: nil, completedPages: 0, totalPages: 0, message: "대기 중")
    )

    init() {
        statusItem.button?.title = "VOCR"
        statusItem.menu = makeMenu(for: lastState)
    }

    func configure(
        showWindow: @escaping () -> Void,
        pause: @escaping () -> Void,
        resume: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.showWindowAction = showWindow
        self.pauseAction = pause
        self.resumeAction = resume
        self.cancelAction = cancel
        statusItem.menu = makeMenu(for: lastState)
    }

    func update(_ state: VOCRJobState) {
        lastState = state
        statusItem.button?.title = state.menuTitle
        statusItem.menu = makeMenu(for: state)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func makeMenu(for state: VOCRJobState) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Apple Vision OCR", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: state.progress.currentFile ?? state.progress.message, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(state.progress.completedPages) / \(state.progress.totalPages) pages", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(state.progress.percent)%", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "상세 창 보기", action: #selector(showWindowSelected), keyEquivalent: ""))

        switch state.runState {
        case .paused:
            menu.addItem(NSMenuItem(title: "이어서 진행", action: #selector(resumeSelected), keyEquivalent: ""))
        case .running:
            menu.addItem(NSMenuItem(title: "일시정지", action: #selector(pauseSelected), keyEquivalent: ""))
        case .idle, .completed, .failed, .canceled:
            break
        }

        if state.runState != .completed {
            menu.addItem(NSMenuItem(title: "취소", action: #selector(cancelSelected), keyEquivalent: ""))
        }

        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func showWindowSelected() {
        showWindowAction?()
    }

    @objc private func pauseSelected() {
        pauseAction?()
    }

    @objc private func resumeSelected() {
        resumeAction?()
    }

    @objc private func cancelSelected() {
        cancelAction?()
    }
}
```

- [ ] **Step 2: Wire status item into window controller**

In `VOCRWindowController`, add:

```swift
private let statusItemController = StatusItemController()
private let jobController = OCRJobController()
```

In `init(inputURLs:)`, after `buildUI()`, configure:

```swift
statusItemController.configure(
    showWindow: { [weak self] in
        self?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    },
    pause: { [weak self] in
        self?.jobController.pause()
    },
    resume: { [weak self] in
        self?.jobController.resume()
    },
    cancel: { [weak self] in
        self?.jobController.cancel()
    }
)
```

Set progress callbacks:

```swift
jobController.onProgress = { [weak self] state in
    self?.statusItemController.update(state)
    self?.statusLabel.stringValue = state.progress.message
}
jobController.onComplete = { [weak self] in
    self?.statusLabel.stringValue = "완료"
}
```

- [ ] **Step 3: Build and manual menu test**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR
.build/debug/VOCR Samples/sample.pdf
```

Expected:

- Menu bar shows `VOCR`.
- Right-clicking the menu bar item shows `상세 창 보기` and `취소`.
- Closing the app removes the menu bar item.

- [ ] **Step 4: Commit**

```bash
git add Sources/VOCR
git commit -m "Add VOCR menu bar controls" \
  -m "Intent: Add menu bar progress surface and pause, resume, cancel menu controls for VOCR." \
  -m "Context: The user wants progress outside Automator gear progress, with right-click menu controls from the menu bar item." \
  -m "Constraint: Menu items reflect state; only one of 일시정지 or 이어서 진행 is visible at a time." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR; .build/debug/VOCR Samples/sample.pdf." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 7: Wire GUI Options To OCR Execution

**Files:**
- Modify: `Sources/VOCR/VOCRWindowController.swift`
- Modify: `Sources/AppleVisionOCRCore/CLIOptions.swift` or create `Sources/AppleVisionOCRCore/OCRRunOptions.swift`

- [ ] **Step 1: Add option-to-CLIOptions builder**

In `VOCRWindowController`, add:

```swift
private func makeOptions(for inputURL: URL) throws -> CLIOptions {
    let writesText = textCheckbox.state == .on
    let writesPDF = pdfCheckbox.state == .on
    let includesPageBreaks = pageBreaksCheckbox.state == .on
    _ = try OCRJobOutputMode(writesPDF: writesPDF, writesText: writesText, includesPageBreaks: includesPageBreaks)

    let pdfOutputURL = writesPDF ? try UniqueOutputPathResolver.availablePDFOutputURL(for: inputURL) : try OutputPathResolver.defaultOutputURL(for: inputURL)
    let textOutputURL = writesText ? try UniqueOutputPathResolver.availableTextOutputURL(for: inputURL) : nil

    return CLIOptions(
        inputURL: inputURL,
        outputURL: pdfOutputURL,
        txtOutputURL: textOutputURL,
        includePageBreaks: includesPageBreaks,
        languages: ["ko", "en"],
        recognitionLevel: .accurate,
        dryRun: false
    )
}
```

If `CLIOptions` initializer is not public, make it public in `AppleVisionOCRCore`.

- [ ] **Step 2: Replace start button placeholder**

Replace `startPressed` implementation with:

```swift
@objc private func startPressed() {
    guard textCheckbox.state == .on || pdfCheckbox.state == .on else {
        statusLabel.stringValue = "TXT 또는 PDF 중 하나를 선택하세요."
        return
    }

    guard let firstInput = inputURLs.first else {
        statusLabel.stringValue = "선택된 PDF가 없습니다."
        return
    }

    do {
        let options = try makeOptions(for: firstInput)
        startButton.isEnabled = false
        jobController.start(options: options)
    } catch {
        statusLabel.stringValue = error.localizedDescription
    }
}
```

This step supports one selected PDF first. Multi-file queue support is added in the next task.

- [ ] **Step 3: Replace cancel button placeholder**

Replace `cancelPressed` with:

```swift
@objc private func cancelPressed() {
    jobController.cancel()
    statusLabel.stringValue = "취소 요청됨"
}
```

- [ ] **Step 4: Run sample app execution**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR
.build/debug/VOCR Samples/sample.pdf
```

Manual expected behavior:

- Default PDF-only run creates `Samples/sample_ocr(1).pdf` or the next available sibling.
- Selecting TXT and page breaks creates `Samples/sample(1).txt` or the next available sibling with `===== Page 1 =====`.
- Menu bar percent changes during OCR.

- [ ] **Step 5: Process sweep**

Run:

```bash
ps -axo pid,comm,args | rg -i 'VOCR|apple-vision-ocr|swift|OwlOCR|python|node|uv'
```

Expected: no task-created VOCR, apple-vision-ocr, Swift build, OwlOCR, Python, Node, or uv process remains except the `ps` and `rg` commands and unrelated long-running user applications.

- [ ] **Step 6: Commit**

```bash
git add Sources/VOCR Sources/AppleVisionOCRCore
git commit -m "Wire VOCR window to OCR execution" \
  -m "Intent: Let the VOCR detail window run Apple Vision OCR with PDF, TXT, and page-divided TXT options." \
  -m "Context: Finder users choose output modes in the app instead of separate Quick Action menu entries." \
  -m "Constraint: This task handles one input PDF; multi-file queue support follows as a separate contained task." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR; .build/debug/VOCR Samples/sample.pdf." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 8: Add Multi-File Queue Progress

**Files:**
- Modify: `Sources/VOCR/OCRJobController.swift`
- Modify: `Sources/VOCR/VOCRWindowController.swift`

- [ ] **Step 1: Extend job controller start API**

Replace:

```swift
func start(options: CLIOptions)
```

with:

```swift
func start(optionsList: [CLIOptions])
```

Implementation outline:

```swift
func start(optionsList: [CLIOptions]) {
    task = Task.detached { [pipeline, control, progressStore, jobID] in
        for options in optionsList {
            if control.isCanceled {
                break
            }
            do {
                try pipeline.run(options: options, control: control) { event in
                    progressStore?.write(event: event, jobID: jobID)
                    Task { @MainActor [weak self] in
                        self?.onProgress?(VOCRJobState(runState: control.isPaused ? .paused : .running, progress: event))
                    }
                }
            } catch {
                let failedEvent = OCRProgressEvent(
                    stage: .failed,
                    currentFile: options.inputURL.lastPathComponent,
                    completedPages: 0,
                    totalPages: 0,
                    message: error.localizedDescription
                )
                Task { @MainActor [weak self] in
                    self?.onProgress?(VOCRJobState(runState: .failed(error.localizedDescription), progress: failedEvent))
                }
                return
            }
        }
        Task { @MainActor [weak self] in
            self?.onComplete?()
        }
    }
}
```

- [ ] **Step 2: Build options for all inputs**

In `VOCRWindowController.startPressed`, replace single input logic with:

```swift
do {
    let optionsList = try inputURLs.map { try makeOptions(for: $0) }
    startButton.isEnabled = false
    jobController.start(optionsList: optionsList)
} catch {
    statusLabel.stringValue = error.localizedDescription
}
```

- [ ] **Step 3: Manual multi-file test**

Prepare:

```bash
mkdir -p .build/vocr-multifile-test
cp Samples/sample.pdf .build/vocr-multifile-test/sample-a.pdf
cp Samples/sample.pdf .build/vocr-multifile-test/sample-b.pdf
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --product VOCR
.build/debug/VOCR .build/vocr-multifile-test/sample-a.pdf .build/vocr-multifile-test/sample-b.pdf
```

Expected: running PDF-only mode creates:

```text
.build/vocr-multifile-test/sample-a_ocr.pdf
.build/vocr-multifile-test/sample-b_ocr.pdf
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VOCR
git commit -m "Add VOCR multi-file queue" \
  -m "Intent: Let VOCR process all selected Finder PDFs in one queued run." \
  -m "Context: Finder Quick Action can pass multiple selected PDFs, and progress should continue through each file." \
  -m "Constraint: Files are processed sequentially to avoid concurrent OCR runs and keep progress predictable." \
  -m "Tested: Manual two-sample run through .build/debug/VOCR." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 9: Package VOCR.app And Install Single Finder Quick Action

**Files:**
- Create: `scripts/package-vocr-app.sh`
- Create: `scripts/vocr-finder-action.sh`
- Create: `scripts/install-vocr-quick-action.sh`
- Modify: `README.md`

- [ ] **Step 1: Create Finder wrapper**

Create `scripts/vocr-finder-action.sh`:

```bash
#!/bin/zsh
set -uo pipefail

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LOG="$HOME/Library/Logs/vocr-quick-action.log"
mkdir -p "$(dirname "$LOG")"
exec 1>>"$LOG"
exec 2>>"$LOG"

echo "================================================================="
echo "[$(date)] Starting VOCR Quick Action"
echo "Arguments: $@"

APP="${VOCR_APP:-$HOME/Applications/VOCR.app}"
if [[ ! -d "$APP" ]]; then
  echo "VOCR app not found: $APP"
  osascript -e 'display notification "VOCR.app을 찾지 못했습니다." with title "Apple Vision OCR"' >/dev/null 2>&1 || true
  exit 127
fi

if [[ "$#" -eq 0 ]]; then
  echo "No files received from Finder"
  osascript -e 'display notification "선택된 PDF가 없습니다." with title "Apple Vision OCR"' >/dev/null 2>&1 || true
  exit 1
fi

open -n "$APP" --args "$@"
```

- [ ] **Step 2: Create app packaging script**

Create `scripts/package-vocr-app.sh`:

```bash
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/VOCR.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release --product VOCR

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/VOCR" "$MACOS/VOCR"
chmod 755 "$MACOS/VOCR"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>VOCR</string>
  <key>CFBundleIdentifier</key>
  <string>dev.oth.vocr</string>
  <key>CFBundleName</key>
  <string>VOCR</string>
  <key>CFBundleDisplayName</key>
  <string>VOCR</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
```

- [ ] **Step 3: Create install script**

Create `scripts/install-vocr-quick-action.sh`:

```bash
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT/.build/VOCR.app"
APP_DEST="$HOME/Applications/VOCR.app"
BIN_DEST="$HOME/.local/bin"
SERVICE_DEST="$HOME/Library/Services/Apple Vision OCR.workflow"

cd "$ROOT"
"$ROOT/scripts/package-vocr-app.sh"

mkdir -p "$HOME/Applications" "$BIN_DEST" "$HOME/Library/Services"
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"
cp "$ROOT/.build/release/apple-vision-ocr" "$BIN_DEST/apple-vision-ocr"
cp "$ROOT/scripts/vocr-finder-action.sh" "$BIN_DEST/vocr-finder-action"
chmod 755 "$BIN_DEST/apple-vision-ocr" "$BIN_DEST/vocr-finder-action"

rm -rf "$SERVICE_DEST"
mkdir -p "$SERVICE_DEST/Contents"
cat > "$SERVICE_DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSServices</key>
  <array/>
</dict>
</plist>
PLIST

cat > "$SERVICE_DEST/Contents/document.wflow" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AMApplicationBuild</key>
  <string>533</string>
  <key>AMApplicationVersion</key>
  <string>2.10</string>
  <key>AMDocumentVersion</key>
  <string>2</string>
  <key>actions</key>
  <array>
    <dict>
      <key>action</key>
      <dict>
        <key>ActionBundlePath</key>
        <string>/System/Library/Automator/Run Shell Script.action</string>
        <key>ActionName</key>
        <string>셸 스크립트 실행</string>
        <key>ActionParameters</key>
        <dict>
          <key>COMMAND_STRING</key>
          <string>#!/bin/zsh
exec "$HOME/.local/bin/vocr-finder-action" "$@"</string>
          <key>CheckedForUserDefaultShell</key>
          <true/>
          <key>inputMethod</key>
          <integer>1</integer>
          <key>shell</key>
          <string>/bin/zsh</string>
          <key>source</key>
          <string></string>
        </dict>
        <key>BundleIdentifier</key>
        <string>com.apple.RunShellScript</string>
      </dict>
      <key>isViewVisible</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>connectors</key>
  <dict/>
  <key>workflowMetaData</key>
  <dict>
    <key>applicationBundleID</key>
    <string>com.apple.finder</string>
    <key>inputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject.PDF</string>
    <key>outputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>presentationMode</key>
    <integer>15</integer>
    <key>processesInput</key>
    <false/>
    <key>serviceApplicationBundleID</key>
    <string>com.apple.finder</string>
    <key>serviceInputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject.PDF</string>
    <key>serviceOutputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>serviceProcessesInput</key>
    <false/>
    <key>systemImageName</key>
    <string>doc.text.magnifyingglass</string>
    <key>useAutomaticInputType</key>
    <false/>
    <key>workflowTypeIdentifier</key>
    <string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict>
</plist>
PLIST

echo "Installed $APP_DEST"
echo "Installed $SERVICE_DEST"
```

- [ ] **Step 4: Make scripts executable**

Run:

```bash
chmod +x scripts/package-vocr-app.sh scripts/install-vocr-quick-action.sh scripts/vocr-finder-action.sh
```

- [ ] **Step 5: Update README**

Add:

```markdown
## Finder GUI Install

```bash
scripts/install-vocr-quick-action.sh
```

This installs:

- `~/Applications/VOCR.app`
- `~/.local/bin/apple-vision-ocr`
- `~/.local/bin/vocr-finder-action`
- `~/Library/Services/Apple Vision OCR.workflow`

Finder shows one Quick Action named `Apple Vision OCR`. The app window controls TXT/PDF/page-divided output, while the menu bar item shows progress and exposes `일시정지`, `이어서 진행`, and `취소`.
```

- [ ] **Step 6: Build app package**

Run:

```bash
scripts/package-vocr-app.sh
```

Expected:

```text
<repo>/.build/VOCR.app
```

- [ ] **Step 7: Commit**

```bash
git add scripts README.md
git commit -m "Add VOCR app packaging and Finder installer" \
  -m "Intent: Package VOCR.app and install one Apple Vision OCR Finder Quick Action." \
  -m "Context: Finder should show one menu item that launches the app rather than multiple VOCR service entries." \
  -m "Constraint: The install script writes only the expected user-local app, bin, log, and Services paths." \
  -m "Tested: scripts/package-vocr-app.sh." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Task 10: Final Verification And Process Cleanup

**Files:**
- Modify only if verification finds a defect.

- [ ] **Step 1: Run full tests**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test
```

Expected: PASS.

- [ ] **Step 2: Build release products**

Run:

```bash
env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift build -c release
scripts/package-vocr-app.sh
```

Expected: both commands PASS.

- [ ] **Step 3: Install local Quick Action**

Run with user approval because it writes outside the repo:

```bash
scripts/install-vocr-quick-action.sh
```

Expected installed paths:

```text
~/Applications/VOCR.app
~/.local/bin/apple-vision-ocr
~/.local/bin/vocr-finder-action
~/Library/Services/Apple Vision OCR.workflow
```

- [ ] **Step 4: Terminal CLI smoke test**

Run:

```bash
mkdir -p .build/final-smoke
/usr/bin/time -p ~/.local/bin/apple-vision-ocr Samples/sample.pdf --output .build/final-smoke/sample_ocr.pdf --txt-output .build/final-smoke/sample.txt --page-breaks
sed -n '1,20p' .build/final-smoke/sample.txt
```

Expected text starts with:

```text
===== Page 1 =====

HELLO OCR SAMPLE
APPLE VISION TEXT
COPYABLE AFTER OCR
```

- [ ] **Step 5: GUI smoke test**

Run:

```bash
open -n "$HOME/Applications/VOCR.app" --args "$PWD/Samples/sample.pdf"
```

Expected:

- `Apple Vision OCR` window opens.
- Menu bar shows `VOCR`.
- Default PDF option is checked.
- Running creates a unique sibling PDF if `Samples/sample_ocr.pdf` already exists.
- Selecting TXT and page break creates a unique sibling TXT with `===== Page 1 =====`.
- Right-click menu exposes `상세 창 보기`, `일시정지` while running, `이어서 진행` while paused, and `취소`.

- [ ] **Step 6: Finder Quick Action manual test**

Manual:

1. Select `Samples/sample.pdf` in Finder.
2. Right-click.
3. Choose `Quick Actions` or `Services`.
4. Click `Apple Vision OCR`.

Expected:

- `VOCR.app` opens with `sample.pdf`.
- Only one Apple Vision OCR entry is needed for this tool.
- The app and menu bar progress behave the same as the direct app smoke test.

- [ ] **Step 7: Process cleanup check**

Run:

```bash
ps -axo pid,comm,args | rg -i 'VOCR|apple-vision-ocr|swift build|swift test|OwlOCR|python|node|uv'
```

Expected: no task-created processes remain. If `VOCR` is still open from manual testing, quit it. Do not kill unrelated Codex, editor, system, or MCP processes.

- [ ] **Step 8: Final commit if verification fixes were required**

If verification required changes:

```bash
git add <changed-files>
git commit -m "Fix VOCR verification issues" \
  -m "Intent: Address defects found during final VOCR GUI and Finder verification." \
  -m "Context: The app, menu bar progress, and Finder Quick Action must work together without leftover helper processes." \
  -m "Constraint: Only verification defects are fixed in this commit." \
  -m "Tested: env SWIFTPM_HOME=.build/swiftpm-home CLANG_MODULE_CACHE_PATH=.build/module-cache swift test; scripts/package-vocr-app.sh; manual VOCR.app and Finder Quick Action smoke tests." \
  -m "Co-authored-by: OmX <omx@oh-my-codex.dev>"
```

## Self-Review Notes

- Spec coverage: the plan implements one Finder entry, GUI option selection, TXT/PDF/page-divided modes, exact `===== Page N =====` divider, menu bar percentage, right-click menu, pause/resume/cancel, unique outputs, and process cleanup checks.
- Scope: the plan keeps the feature in one coherent subsystem: Finder-launched VOCR GUI sharing the existing OCR core.
- Testing: the plan includes unit tests for mode/path/progress behavior plus manual AppKit and Finder verification.
- Dependency boundary: the plan does not add Python, Node, uv, or OwlOCR dependencies to the Apple Vision path.
