import XCTest
@testable import AppleVisionOCRCore

final class MarkdownLayoutTests: XCTestCase {
    private func region(_ label: String = "text", _ x: CGFloat = 0.1, _ y: CGFloat = 0.2,
                        _ w: CGFloat = 0.8, _ h: CGFloat = 0.3, query: Int = 0) -> LayoutRegion {
        LayoutRegion(query: query, label: label, score: 0.9, rect: CGRect(x: x, y: y, width: w, height: h))
    }
    private func line(_ text: String, _ x: CGFloat = 0.2, _ y: CGFloat = 0.25,
                      _ w: CGFloat = 0.3, _ h: CGFloat = 0.02) -> LayoutLine {
        LayoutLine(text: text, rect: CGRect(x: x, y: y, width: w, height: h))
    }
    private func analyze(_ regions: [LayoutRegion], _ lines: [LayoutLine],
                         crop: (CGRect) -> [LayoutLine] = { _ in [] },
                         table: (CGRect) -> String? = { _ in nil }) -> MarkdownPage {
        MarkdownPageAnalyzer.analyze(pdfPage: 3, regions: regions, lines: lines,
                                        recognizeCrop: crop, recognizeTable: table)
    }
    private func decode(_ logits: [Float], boxes: [Float]? = nil, order: [Float]? = nil,
                        classes: Int = 2, threshold: Float = 0.4) -> [LayoutRegion] {
        let count = logits.count / classes
        return LayoutDecoder.regions(logits: logits, boxes: boxes ?? Array(repeating: 0.5, count: count * 4),
                                     orderLogits: order ?? Array(repeating: 0, count: count * count),
                                     queryCount: count, classCount: classes, threshold: threshold)
    }

    func testDecoderUsesArgmaxAndSigmoidThreshold() {
        let result = decode([-1, 0, -2, -1])
        XCTAssertEqual(result.map(\.label), ["algorithm"])
        XCTAssertEqual(result.first?.score, 0.5)
        XCTAssertEqual(decode([0, 0], threshold: 0.5).first?.label, "abstract")
    }
    func testDecoderConvertsCenterBox() {
        let rect = decode([0, 1], boxes: [0.5, 0.4, 0.6, 0.2])[0].rect
        XCTAssertEqual(rect.minX, 0.2, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 0.3, accuracy: 0.000001)
        XCTAssertEqual(rect.width, 0.6, accuracy: 0.000001)
    }
    func testDecoderVotesIncludeFilteredQueries() {
        // Query 1 is filtered out, but its pairwise vote still puts query 2 first.
        let order: [Float] = [0, -10, 0, 0, 0, -10, 0, 0, 0]
        XCTAssertEqual(decode([1, 0, -9, -9, 1, 0], order: order).map(\.query), [2, 0])
    }
    func testDecoderStableVoteTies() {
        XCTAssertEqual(decode([1, 0, 1, 0, 1, 0]).map(\.query), [0, 1, 2])
    }
    func testAssignmentPrefersSmallestContentAreaAndPreservesLines() {
        let result = analyze([region(), region("paragraph_title", 0.1, 0.2, 0.5, 0.1)],
                             [line("second"), line("first")])
        XCTAssertEqual(result.blocks.map(\.text), ["second first"])
        XCTAssertEqual(result.blocks.first?.kind, .heading)
    }
    func testFootnoteWinsOverSmallerFooter() {
        let result = analyze([region("footnote"), region("footer", 0.2, 0.25, 0.4, 0.03)], [line("4) note")])
        XCTAssertEqual(result.footnotes.map(\.text), ["note"])
        XCTAssertTrue(result.blocks.isEmpty)
    }
    func testFootnoteWinsOverLargerFooter() {
        let result = analyze([region("footer"), region("footnote", 0.2, 0.25, 0.4, 0.03)], [line("4) note")])
        XCTAssertEqual(result.footnotes.map(\.text), ["note"])
        XCTAssertTrue(result.blocks.isEmpty)
    }
    func testHeaderAndNumberAssignedLinesAreDiscardedWhenContentEmpty() {
        let result = analyze([region("header"), region("number", 0.1, 0.7, 0.8, 0.1)],
                             [line("header"), line("number", 0.2, 0.72), line("keep", 0.2, 0.6)])
        XCTAssertEqual(result.blocks.map(\.text), ["keep"])
    }
    func testUnassignedTopLineBecomesCandidate() {
        let result = analyze([region()], [line("running head", 0.2, 0.08), line("body")])
        XCTAssertEqual(result.topCandidates, ["running head"])
        XCTAssertEqual(result.blocks.map(\.text), ["body"])
    }
    func testBottomLargeLogoDropsButNormalLineRemains() {
        let result = analyze([region()], [line("body"), line("body2", 0.2, 0.3),
                                          line("logo", 0.2, 0.9, 0.3, 0.046), line("note", 0.2, 0.96)])
        XCTAssertEqual(result.blocks.map(\.text), ["body\nbody2", "note"])
    }
    func testUnassignedLineAnchorsToItsColumn() {
        let result = analyze([region("text", 0.05, 0.2, 0.4, 0.2), region("text", 0.55, 0.2, 0.4, 0.4)],
                             [line("left", 0.1, 0.25), line("right", 0.6, 0.25), line("tail", 0.1, 0.65)])
        XCTAssertEqual(result.blocks.map(\.text), ["left", "tail", "right"])
    }
    func testNoRegionsProducesOneParagraph() {
        XCTAssertEqual(analyze([], [line("a"), line("b")]).blocks.map(\.text), ["a\nb"])
    }
    func testEmptyRegionReOCRUsesClampedPadding() {
        var crops: [CGRect] = []
        let result = analyze([region("text", 0, 0, 0.2, 0.2)], [], crop: {
            crops.append($0); return [self.line("recovered", 0.01, 0.01)]
        })
        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(crops[0].minX, 0)
        XCTAssertEqual(crops[0].minY, 0)
        XCTAssertEqual(crops[0].width, 0.21, accuracy: 0.000001)
        XCTAssertEqual(crops[0].height, 0.21, accuracy: 0.000001)
        XCTAssertEqual(result.blocks.map(\.text), ["recovered"])
    }
    func testOverlapContainingOriginalCenterDoesNotReOCR() {
        var calls = 0
        let result = analyze([region(), region("paragraph_title", 0.1, 0.2, 0.5, 0.1)], [line("title")], crop: {
            _ in calls += 1; return []
        })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.blocks.count, 1)
    }
    func testReOCRFiltersSmallFragmentsUsingOriginalMedian() {
        let result = analyze([region(), region("footnote", 0.1, 0.7, 0.8, 0.15)], [line("body")], crop: { _ in
            [self.line("fragment", 0.2, 0.71, 0.3, 0.0072), self.line("9) recovered", 0.2, 0.74, 0.3, 0.0216)]
        })
        XCTAssertEqual(result.footnotes.map(\.text), ["recovered"])
    }
    func testZeroMedianSkipsHeightFilter() {
        XCTAssertEqual(analyze([region()], [], crop: { _ in [self.line("tiny", 0.2, 0.25, 0.3, 0)] }).blocks.map(\.text), ["tiny"])
    }
    func testNumberCropFindsStandaloneDigitsAfterBullet() {
        var calls = 0
        let result = analyze([region("number")], [line("ignored")], crop: { _ in
            calls += 1; return [self.line("123456 • 713")]
        })
        XCTAssertEqual(result.printedPage, 713)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(result.blocks.isEmpty)
    }
    func testBottomTextCorrectionAndFinalFootnoteCannotAnchor() {
        let result = analyze([region(), region("text", 0.1, 0.7, 0.8, 0.1)],
                             [line("body"), line("11) note", 0.2, 0.72), line("tail", 0.2, 0.82)])
        XCTAssertEqual(result.footnotes.map(\.marker), ["11"])
        XCTAssertEqual(result.blocks.map(\.text), ["body", "tail"])
    }
    func testNumberedPageDoesNotTurnEntirePageIntoFootnotes() {
        let result = analyze([region("text", 0.1, 0.6, 0.8, 0.1), region("text", 0.1, 0.8, 0.8, 0.1)],
                             [line("1) one", 0.2, 0.62), line("2) two", 0.2, 0.82)])
        XCTAssertTrue(result.footnotes.isEmpty)
        XCTAssertEqual(result.blocks.map(\.text), ["1) one", "2) two"])
    }
    func testFootnoteMarkers() {
        let cases: [(String, String?, String)] = [
            (" (6) note", "6", "note"), ("4) note", "4", "note"), ("1 note", "1", "note"),
            ("* note", "*", "note"), ("† note", "†", "note"), ("‡ note", "‡", "note"),
            ("1998, pp.4", nil, "1998, pp.4"), ("2004),187.", nil, "2004),187.")
        ]
        for (input, marker, text) in cases {
            let note = analyze([region("footnote")], [line(input)]).footnotes.first
            XCTAssertEqual(note?.marker, marker, input)
            XCTAssertEqual(note?.text, text, input)
        }
    }
    func testEmptyFootnoteAfterMarkerIsSkipped() {
        XCTAssertTrue(analyze([region("footnote")], [line("4) ")]).footnotes.isEmpty)
    }
    func testTwoLineTitleAndHeadingJoinWithSpaces() {
        let result = analyze([region("doc_title"), region("paragraph_title", 0.1, 0.6, 0.8, 0.1)],
                             [line("title"), line("second", 0.2, 0.3), line("heading", 0.2, 0.62)])
        XCTAssertEqual(result.blocks.map(\.kind), [.title, .heading])
        XCTAssertEqual(result.blocks.map(\.text), ["title second", "heading"])
    }
    func testParagraphEscapesHashAtEachLineStart() {
        XCTAssertEqual(analyze([], [line("# a"), line("## b"), line("c # d\n# embedded")]).blocks.first?.text,
                       "\\# a\n\\## b\nc # d\n\\# embedded")
    }
    func testTableSuccessUsesPaddedCropAndFallbackKeepsLines() {
        let regions = [region("table")]
        var cropCalls = 0
        let success = analyze(regions, [line("fallback")], crop: { _ in cropCalls += 1; return [] }, table: {
            XCTAssertEqual($0.minX, 0.09, accuracy: 0.000001)
            return "| cell |\n| --- |"
        })
        XCTAssertEqual(success.blocks.first?.kind, .table)
        XCTAssertEqual(cropCalls, 0)
        XCTAssertEqual(analyze(regions, [line("fallback")]).blocks.first?.text, "fallback")
        XCTAssertEqual(analyze(regions, [line("fallback")], table: { _ in "" }).blocks.first?.kind, .paragraph)
    }
    func testRecognitionErrorsPropagate() {
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try MarkdownPageAnalyzer.analyze(
            pdfPage: 3, regions: [region()], lines: [],
            recognizeCrop: { _ in throw Failure.expected }, recognizeTable: { _ in nil }))
        XCTAssertThrowsError(try MarkdownPageAnalyzer.analyze(
            pdfPage: 3, regions: [region("table")], lines: [],
            recognizeCrop: { _ in [] }, recognizeTable: { _ in throw Failure.expected }))
    }
    func testAssignmentContainsBoundaryCenterInclusively() {
        let result = analyze([region("text", 0.2, 0.2, 0.2, 0.2)],
                             [line("edge", 0.19, 0.25, 0.01, 0.02)])
        XCTAssertEqual(result.blocks.map(\.text), ["edge"])
    }
}
