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
    func testReadingRowsOrderOriginalCropUnassignedAndFootnoteLines() {
        let shuffled = [line("right", 0.6, 0.249), line("next", 0.2, 0.28), line("left", 0.2, 0.25)]
        XCTAssertEqual(analyze([region()], shuffled).blocks.map(\.text), ["left\nright\nnext"])
        XCTAssertEqual(analyze([region()], [], crop: { _ in shuffled }).blocks.map(\.text), ["left\nright\nnext"])
        XCTAssertEqual(analyze([], shuffled).blocks.map(\.text), ["right\nnext\nleft"])
        XCTAssertEqual(analyze([region("footnote")], shuffled).footnotes.map(\.text), ["left\nright\nnext"])
        let notes = analyze([region("footnote")], [line("2017), 63.", 0.2, 0.29), line("30) Krs Fiuser, ...")])
        XCTAssertEqual(notes.footnotes, [.init(marker: "30", text: "Krs Fiuser, ...\n2017), 63.")])
        let chain = [line("third", 0.1, 0.266), line("second", 0.2, 0.258), line("first", 0.3, 0.25)]
        XCTAssertEqual(analyze([], chain).blocks.map(\.text), ["third\nsecond\nfirst"])
    }

    func testFootnoteRegionSplitsContinuationAndSequentialMarkersOnly() {
        let result = analyze([region("footnote")], [
            line("2017), 63.", 0.2, 0.33), line("30) Krs Fiuser, ...", 0.2, 0.29),
            line("...1993), 211.", 0.2, 0.25)
        ])
        XCTAssertEqual(result.footnotes, [.init(marker: nil, text: "...1993), 211."),
                                       .init(marker: "30", text: "Krs Fiuser, ...\n2017), 63.")])
        let sequential = analyze([region("footnote")], [line("29) first"), line("30) next", 0.2, 0.29), line("32) retained", 0.2, 0.33)])
        XCTAssertEqual(sequential.footnotes, [.init(marker: "29", text: "first"), .init(marker: "30", text: "next"),
                                            .init(marker: "32", text: "retained")])
        let symbol = analyze([region("footnote")], [line("* first"), line("30) next", 0.2, 0.29)])
        XCTAssertEqual(symbol.footnotes.map(\.marker), ["*", "30"])
    }

    func testBottomReferenceContentBecomesFootnote() {
        let result = analyze([region(), region("reference_content", 0.1, 0.7, 0.8, 0.1)],
                             [line("body"), line("47) Ronald Bamett, ...", 0.2, 0.72)])
        XCTAssertEqual(result.footnotes, [.init(marker: "47", text: "Ronald Bamett, ...")])
        XCTAssertEqual(result.blocks.map(\.text), ["body"])
    }

    func testFootnoteMarkerAttachedToLatinAuthorPreservesYears() {
        for (input, marker, text) in [("1Sidney Greidanus, Preaching Christ ...", "1", "Sidney Greidanus, Preaching Christ ..."),
                                      ("1990년대에", nil, "1990년대에"), ("2017), 63.", nil, "2017), 63.")] {
            XCTAssertEqual(analyze([region("footnote")], [line(input)]).footnotes, [.init(marker: marker, text: text)])
        }
    }

    func testFootnoteNoiseSkipsTinyNonlettersAfterParsing() {
        for input in ["§", "1^"] {
            XCTAssertTrue(analyze([region("footnote")], [line(input)]).footnotes.isEmpty, input)
        }
        for input in ["2017), 63.", "가", "A"] {
            XCTAssertEqual(analyze([region("footnote")], [line(input)]).footnotes.map(\.text), [input])
        }
    }

    func testMarkedFootnotesPreserveShortNonletterText() {
        for (input, marker, text) in [("1)42", "1", "42"), ("1)§1", "1", "§1"),
                                      ("1) 42", "1", "42"), ("1) §1", "1", "§1"),
                                      ("* §", "*", "§"), ("2) ^", "2", "^")] {
            XCTAssertEqual(analyze([region("footnote")], [line(input)]).footnotes,
                           [.init(marker: marker, text: text)], input)
        }
        XCTAssertTrue(analyze([region("footnote")], [line("1)")]).footnotes.isEmpty)
    }

    func testFootnoteRegionSplitsAllParsedNumericMarkerForms() {
        for (first, next) in [("29) First", "30) Next"), ("(29) First", "(30) Next"),
                              ("29 First", "30 Next"), ("29First", "30Next")] {
            let result = analyze([region("footnote")], [line(first), line(next, 0.2, 0.29)])
            XCTAssertEqual(result.footnotes, [.init(marker: "29", text: "First"),
                                            .init(marker: "30", text: "Next")], next)
            let continuation = analyze([region("footnote")], [line("continuation"), line(next, 0.2, 0.29)])
            XCTAssertEqual(continuation.footnotes.map(\.marker), [nil, "30"], next)
        }
    }

    func testParenthesizedFootnotesSplitIncreasingNumbersButKeepNestedLists() {
        for (first, next) in [("29) First", "32) Next"), ("(29) First", "(32) Next")] {
            XCTAssertEqual(analyze([region("footnote")], [line(first), line(next, 0.2, 0.29)]).footnotes,
                           [.init(marker: "29", text: "First"), .init(marker: "32", text: "Next")])
        }
        let nested = analyze([region("footnote")], [line("29) First"), line("1) nested", 0.2, 0.29),
                                                   line("2) nested next", 0.2, 0.33)])
        XCTAssertEqual(nested.footnotes, [.init(marker: "29", text: "First\n1) nested\n2) nested next")])
        for next in ["32 Next", "32Next", "29) repeated"] {
            XCTAssertEqual(analyze([region("footnote")], [line("29) First"), line(next, 0.2, 0.29)]).footnotes,
                           [.init(marker: "29", text: "First\n" + next)])
        }
    }

    func testSentenceEndingHeadingBecomesParagraph() {
        for input in ["조치를 취해야 할 것이다.24)", "조치를 취해야 할 것이다. (24)", "조치를 취해야 할 것이다.  "] {
            XCTAssertEqual(analyze([region("paragraph_title")], [line(input)]).blocks, [.init(kind: .paragraph, text: input)])
            let top = analyze([region("paragraph_title", 0.1, 0.08, 0.8, 0.04)], [line(input, 0.2, 0.09)])
            XCTAssertEqual(top.topCandidates + top.blocks, [.init(kind: .paragraph, text: input)])
        }
        XCTAssertEqual(analyze([region("paragraph_title")], [line("1. 문제제기")]).blocks.first?.kind, .heading)
    }

    func testMultilevelSectionHeadingKeepsSentenceEnding() {
        let input = " 1.2.1. 설교는 신학이다. "
        XCTAssertEqual(analyze([region("paragraph_title")], [line(input)]).blocks,
                       [.init(kind: .heading, text: input)])
    }

    func testOnlyShortSingleLineTextSectionsBecomeHeadings() {
        for input in ["1.2.1. 설교와 신학", " 1.2. 설교는 신학이다. ", "1.2. " + String(repeating: "가", count: 55)] {
            XCTAssertEqual(analyze([region()], [line(input)]).blocks,
                           [.init(kind: .heading, text: input)], input)
            let top = analyze([region("text", 0.1, 0.08, 0.8, 0.04)], [line(input, 0.2, 0.09)])
            XCTAssertEqual(top.topCandidates, [.init(kind: .heading, text: input)], input)
        }
        for input in ["1. 본문에서 말하고 있는 것은 무엇인가?", "1. 서론", "1.5 배",
                      "1.2.1. 설교와 신학 ........ 3", "1.2. 설교와 신학 … 3",
                      "1.2. " + String(repeating: "가", count: 56)] {
            XCTAssertEqual(analyze([region()], [line(input)]).blocks,
                           [.init(kind: .paragraph, text: input)], input)
        }
        XCTAssertEqual(analyze([region()], [line("1.2. 설교와 신학"), line("이어지는 본문", 0.2, 0.29)]).blocks.first?.kind,
                       .paragraph)
        for label in ["reference_content", "figure_title", "table"] {
            XCTAssertEqual(analyze([region(label)], [line("1.2. 설교와 신학")]).blocks.first?.kind, .paragraph, label)
        }
    }

    func testTopContentCandidatePreservesKindAndUnassignedReadingOrder() {
        let result = analyze([region("paragraph_title", 0.1, 0.08, 0.8, 0.04), region()],
                             [line("body"), line("722• 신학과 실천(Theology and Praxis)", 0.2, 0.09), line("top", 0.2, 0.03)])
        XCTAssertEqual(result.topCandidates, [.init(kind: .paragraph, text: "top"), .init(kind: .heading, text: "722• 신학과 실천(Theology and Praxis)")])
        XCTAssertEqual(result.blocks.map(\.text), ["body"])
        let heading = analyze([region("paragraph_title", 0.1, 0.08, 0.8, 0.04)], [line("1. 문제제기", 0.2, 0.09)])
        XCTAssertEqual(heading.topCandidates, [.init(kind: .heading, text: "1. 문제제기")])
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
        XCTAssertEqual(result.topCandidates, [.init(kind: .paragraph, text: "running head")])
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
    func testNoRegionsPreservesVisionColumnReadingOrder() {
        let result = analyze([], [line("L1", 0.1, 0.2), line("L2", 0.1, 0.3),
                                  line("R1", 0.6, 0.2), line("R2", 0.6, 0.3)])
        XCTAssertEqual(result.blocks.map(\.text), ["L1\nL2\nR1\nR2"])
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
    func testReOCRFiltersPaddingNeighbourWithoutSuppressingRecovery() {
        for label in ["text", "footnote"] {
            var calls = 0
            let neighbour = line("neighbour", 0.402, 0.25, 0.01)
            let result = analyze([region(label, 0.2, 0.2, 0.2, 0.2)], [neighbour], crop: {
                calls += 1
                XCTAssertEqual($0.maxX, 0.41, accuracy: 0.000001)
                return [self.line("recovered", 0.22, 0.25, 0.1), neighbour]
            })
            XCTAssertEqual(calls, 1, label)
            XCTAssertEqual(result.blocks.map(\.text), label == "text" ? ["neighbour", "recovered"] : ["neighbour"])
            XCTAssertEqual(result.footnotes.map(\.text), label == "footnote" ? ["recovered"] : [])
        }
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
