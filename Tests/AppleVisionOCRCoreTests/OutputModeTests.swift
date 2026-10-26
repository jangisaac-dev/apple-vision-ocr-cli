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

    func testJobOptionsRequirePDFURLForPDFMode() {
        XCTAssertThrowsError(try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: nil,
            outputMode: .searchablePDF
        )) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .missingPDFOutputURL)
        }
    }

    func testJobOptionsRejectFastRecognitionWithUnsupportedLanguages() {
        XCTAssertThrowsError(try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: URL(fileURLWithPath: "/tmp/input.txt"),
            outputMode: .plainText,
            languages: ["ko", "en"],
            recognitionLevel: .fast
        )) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .unsupportedRecognitionLanguage)
        }
    }

    func testJobOptionsDefaultToSharedParallelismDefault() throws {
        let options = try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: URL(fileURLWithPath: "/tmp/input.txt"),
            outputMode: .plainText
        )

        XCTAssertEqual(options.pageParallelism, .default)
    }
    func testMarkdownIsExclusive() throws {
        XCTAssertTrue(OCRJobOutputMode.markdown.writesMarkdown)
        for (pdf, text, breaks) in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertThrowsError(try OCRJobOutputMode(writesPDF: pdf, writesText: text, includesPageBreaks: breaks, writesMarkdown: true)) {
                XCTAssertEqual($0 as? OCRJobOptionError, .markdownIsExclusive)
            }
        }
    }

    func testMarkdownRequiresExactlyOneOutputURL() throws {
        let input = URL(fileURLWithPath: "/tmp/input.pdf")
        let markdown = URL(fileURLWithPath: "/tmp/input.md")
        let pages = URL(fileURLWithPath: "/tmp/pages.json")
        for (md, json): (URL?, URL?) in [(nil, nil), (markdown, pages)] {
            XCTAssertThrowsError(try OCRJobOptions(inputURL: input, pdfOutputURL: nil, textOutputURL: nil,
                                                 outputMode: .markdown, markdownOutputURL: md, markdownPagesOutputURL: json)) {
                XCTAssertEqual($0 as? OCRJobOptionError, .missingMarkdownOutputURL)
            }
        }
        for (md, json): (URL?, URL?) in [(markdown, nil), (nil, pages)] {
            XCTAssertNoThrow(try OCRJobOptions(inputURL: input, pdfOutputURL: nil, textOutputURL: nil,
                                             outputMode: .markdown, markdownOutputURL: md, markdownPagesOutputURL: json))
        }
    }

}
