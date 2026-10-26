import XCTest
@testable import AppleVisionOCRCore

final class MarkdownDocumentTests: XCTestCase {
    func testTableLeavesRowAndColumnSpansEmptyExceptUpperLeft() {
        XCTAssertEqual(MarkdownTable.render(cells: [
            .init(rows: 0...1, columns: 0...0, text: "병합 머리칸"),
            .init(rows: 0...0, columns: 1...2, text: "가로 병합"),
            .init(rows: 1...1, columns: 1...1, text: "B"),
            .init(rows: 1...1, columns: 2...2, text: "C"),
            .init(rows: 2...2, columns: 0...2, text: "세 칸 병합")
        ]), "| 병합 머리칸 | 가로 병합 |  |\n| --- | --- | --- |\n|  | B | C |\n| 세 칸 병합 |  |  |")
    }

    func testTableEscapesPipesAndNormalizesCellWhitespace() {
        XCTAssertEqual(MarkdownTable.render(cells: [
            .init(rows: 0...0, columns: 0...0, text: " A|B\nC ")
        ]), "| A\\|B C |\n| --- |")
    }

    func testEmptyTable() {
        XCTAssertEqual(MarkdownTable.render(cells: []), "")
    }

    func testExactTwoPageOutput() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(1, printed: 709, blocks: [
                .init(kind: .title, text: "논문 제목"),
                .init(kind: .heading, text: "첫 절"),
                .init(kind: .paragraph, text: "금지했고,4) 장자크\n다음 줄"),
                .init(kind: .table, text: "| A |\n| --- |")
            ], notes: [.init(marker: "4", text: "첫 줄\n둘째 줄")]),
            page(2, printed: 710, blocks: [.init(kind: .paragraph, text: "본문")], notes: [.init(marker: "*", text: "기호 각주")])
        ])
        XCTAssertEqual(text, "[p. 709]\n\n# 논문 제목\n\n## 첫 절\n\n금지했고,[^4] 장자크\n다음 줄\n\n| A |\n| --- |\n\n[p. 710] [^p2-s1]\n\n본문\n\n<!-- footnotes -->\n\n[^4]: 첫 줄\n    둘째 줄\n[^p2-s1]: 기호 각주\n")
        assertDefinitionsReferencedOnce(text)
    }

    func testRestartedNumbersAndRepeatedNumbersUseUniqueLabelsAndOccurrences() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(1, text: "앞1) 끝", notes: [.init(marker: "1", text: "첫째")]),
            page(2, text: "앞1) 중간1) 끝", notes: [
                .init(marker: "1", text: "다시 시작"),
                .init(marker: "1", text: "또 반복")
            ])
        ])
        XCTAssertTrue(text.contains("앞[^1] 끝"))
        XCTAssertTrue(text.contains("앞[^1-p2] 중간[^1-p2-2] 끝"))
        assertDefinitionsReferencedOnce(text)
    }

    func testRepeatedNumberWithoutSecondOccurrenceFallsBackToPageMarker() {
        let text = MarkdownDocumentRenderer.render(pages: [page(1, text: "앞1) 끝", notes: [
            .init(marker: "1", text: "첫째"), .init(marker: "1", text: "둘째")
        ])])
        XCTAssertTrue(text.hasPrefix("[PDF p. 1] [^1-p1]\n\n앞[^1] 끝"))
        assertDefinitionsReferencedOnce(text)
    }

    func testFirstUnmarkedFootnoteContinuesPreviousLastDefinitionAndCanChain() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(1, notes: [.init(marker: "1", text: "첫 각주"), .init(marker: "2", text: "계속될 각주")]),
            page(2, notes: [.init(marker: nil, text: "1998, pp. 20–21.")]),
            page(3, notes: [.init(marker: nil, text: "다음 이어짐"), .init(marker: nil, text: "별개 각주")])
        ])
        XCTAssertTrue(text.contains("[^2]: 계속될 각주\n    1998, pp. 20–21.\n    다음 이어짐"))
        XCTAssertTrue(text.contains("[^p3-u2]: 별개 각주"))
        XCTAssertFalse(text.contains("[^p2-u1]"))
        assertDefinitionsReferencedOnce(text)
    }

    func testUnmarkedFootnotesDoNotCrossMissingOrFootnoteFreePages() {
        for middle in [[], [page(2)]] {
            let text = MarkdownDocumentRenderer.render(pages:
                [page(1, notes: [.init(marker: "1", text: "첫째")])] + middle
                + [page(3, notes: [.init(marker: nil, text: "별개")])]
            )
            XCTAssertTrue(text.contains("[^p3-u1]: 별개"))
            assertDefinitionsReferencedOnce(text)
        }
        let first = MarkdownDocumentRenderer.render(pages: [page(1, notes: [.init(marker: nil, text: "처음")])])
        XCTAssertTrue(first.contains("[^p1-u1]: 처음"))
        assertDefinitionsReferencedOnce(first)
    }

    func testReferenceBoundaryFixtures() {
        let cases: [(String, String, String)] = [
            ("(창 1:20-23), 여섯째", "23", "(창 1:20-23), 여섯째"),
            ("(표1) 참조", "1", "(표1) 참조"),
            ("설교인가?1) 다음", "1", "설교인가?[^1] 다음"),
            ("1) 줄 시작\n1) 다음 줄", "1", "1) 줄 시작\n1) 다음 줄"),
            ("금지했고,4) 장자크", "4", "금지했고,[^4] 장자크"),
            ("앞11) 다음", "1", "앞11) 다음"),
            ("앞1)다음", "1", "앞1)다음"),
            ("(윗줄\n앞1) 다음", "1", "(윗줄\n앞[^1] 다음"),
            ("인용)1). 다음", "1", "인용)[^1]. 다음")
        ]
        for (input, number, expected) in cases {
            let text = MarkdownDocumentRenderer.render(pages: [page(1, text: input, notes: [.init(marker: number, text: "각주")])])
            XCTAssertTrue(text.contains("\n\n" + expected + "\n\n<!-- footnotes -->"), input)
            assertDefinitionsReferencedOnce(text)
        }
    }

    func testOnlyParagraphBlocksReceiveNumericReferences() {
        let text = MarkdownDocumentRenderer.render(pages: [page(1, blocks: [
            .init(kind: .title, text: "제목1)"),
            .init(kind: .heading, text: "소제목1)"),
            .init(kind: .table, text: "표1)"),
            .init(kind: .paragraph, text: "본문1)")
        ], notes: [.init(marker: "1", text: "각주")])])
        XCTAssertTrue(text.contains("# 제목1)\n\n## 소제목1)\n\n표1)\n\n본문[^1]"))
        assertDefinitionsReferencedOnce(text)
    }

    func testRetainedTopCandidatesParticipateInReferenceReplacement() {
        let text = MarkdownDocumentRenderer.render(pages: [page(1, candidates: ["머리말 아닌 본문1) 다음"],
            notes: [.init(marker: "1", text: "각주")])])
        XCTAssertTrue(text.contains("\n\n머리말 아닌 본문[^1] 다음\n\n<!-- footnotes -->"))
        assertDefinitionsReferencedOnce(text)
    }

    func testNeighborNumberRemovesHeaderAndSuppliesPrintedPage() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(3, printed: 711),
            page(2, candidates: ["710• 신학과 실천(Theology and Praxis)", "본문 후보"])
        ])
        XCTAssertEqual(text, "[p. 710]\n\n본문 후보\n\n[p. 711]\n")
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(2, candidates: ["710• 신학과 실천(Theology and Praxis)"])]),
                       "[PDF p. 2]\n\n710• 신학과 실천(Theology and Praxis)\n")
    }

    func testOriginalNeighborsAreUsedWithoutCascadingOrCrossingPageGaps() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(3, candidates: ["102• 머리말"]),
            page(2, candidates: ["101• 머리말"]),
            page(1, printed: 100),
            page(5, candidates: ["104• 머리말"])
        ])
        XCTAssertEqual(text, "[p. 100]\n\n[p. 101]\n\n[PDF p. 3]\n\n102• 머리말\n\n[PDF p. 5]\n\n104• 머리말\n")
    }

    func testCandidateMustContainTheWholeDigitRun() {
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(1, printed: 710, candidates: ["1710• 남김", "710• 지움"])]),
                       "[p. 710]\n\n1710• 남김\n")
    }

    func testEmptyOutputAndTrailingNewlinesHaveOneFinalNewline() {
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: []), "\n")
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(1, text: "본문\n\n")]), "[PDF p. 1]\n\n본문\n")
    }

    func testPageRoundTripsThroughCodable() throws {
        let original = page(2, printed: 710, candidates: ["후보"], text: "본문", notes: [.init(marker: "*", text: "각주")])
        XCTAssertEqual(try JSONDecoder().decode(MarkdownPage.self, from: JSONEncoder().encode(original)), original)
    }

    func testPrintedPageOffsetsUseOriginalNeighborsAndLeaveTiesUnchanged() {
        let text = MarkdownDocumentRenderer.render(pages: [
            page(3, printed: 711), page(4), page(5, printed: 713), page(6, printed: 714),
            page(12, printed: 720), page(13, printed: 121), page(14, candidates: ["722• 신학과 실천(Theology and Praxis)"]),
            page(15, printed: 723), page(16, printed: 724)
        ])
        XCTAssertEqual(text, "[p. 711]\n\n[p. 712]\n\n[p. 713]\n\n[p. 714]\n\n[p. 720]\n\n[p. 721]\n\n[p. 722]\n\n[p. 723]\n\n[p. 724]\n")
        let tied = MarkdownDocumentRenderer.render(pages: [page(1, printed: 101), page(2, printed: 102),
            page(3, printed: 500), page(4, printed: 204), page(5, printed: 205)])
        XCTAssertTrue(tied.contains("[p. 500]"))
    }

    func testInferredPrintedPagesBeforePageOneKeepPDFMarkers() {
        for followingPages in [[page(13, printed: 1)], [page(13, printed: 1), page(14, printed: 2)]] {
            let text = MarkdownDocumentRenderer.render(pages: [page(12, candidates: ["0• 앞부분"])] + followingPages)
            XCTAssertTrue(text.hasPrefix("[PDF p. 12]\n\n0• 앞부분\n\n[p. 1]\n"))
            XCTAssertFalse(text.contains("[p. 0]"))
        }
    }

    func testTopCandidatesKeepHeadingsAndMergeOnlyConsecutiveParagraphs() {
        let original = MarkdownPage(pdfPage: 1, printedPage: nil, topCandidates: [
            .init(kind: .paragraph, text: "first"), .init(kind: .paragraph, text: "second"),
            .init(kind: .heading, text: "1. 문제제기"), .init(kind: .paragraph, text: "third")
        ], blocks: [.init(kind: .paragraph, text: "body")], footnotes: [])
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [original]), "[PDF p. 1]\n\nfirst\nsecond\n\n## 1. 문제제기\n\nthird\n\nbody\n")
    }

    func testHeaderPageNumbersOnlyMatchEligibleLineEdges() {
        let chapter = MarkdownDocumentRenderer.render(pages: [page(1, printed: 1,
            candidates: ["제 1장 서 론", "1. 서론", "1) 항목"])])
        XCTAssertEqual(chapter, "[p. 1]\n\n제 1장 서 론\n1. 서론\n1) 항목\n")
        for (number, header) in [(710, "710• 신학과 실천"), (438, "438 • 신학정론"),
                                 (713, "동물윤리의 역사와 현대적 과제 • 713")] {
            XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(1, printed: number, candidates: [header])]),
                           "[p. \(number)]\n")
        }
    }

    func testUnmatchedClosingParenthesisDoesNotHideLaterOpenParenthesis() {
        let text = MarkdownDocumentRenderer.render(pages: [page(1, text: "가) (표1) 참조. 본문1)",
            notes: [.init(marker: "1", text: "각주")])])
        XCTAssertTrue(text.contains("\n\n가) (표1) 참조. 본문[^1]\n\n"))
        assertDefinitionsReferencedOnce(text)
    }

    func testPrintedPageRestartIsNotOverriddenByOneSidedNeighbors() {
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(1, printed: 100),
            page(2, printed: 101), page(3, printed: 1)]), "[p. 100]\n\n[p. 101]\n\n[p. 1]\n")
        let corrected = MarkdownDocumentRenderer.render(pages: [page(12, printed: 720), page(13, printed: 121),
            page(14), page(15, printed: 723)])
        XCTAssertTrue(corrected.contains("[p. 721]"))
    }

    func testSectionNumberIsNotMistakenForFootnoteReference() {
        let text = MarkdownDocumentRenderer.render(pages: [page(1, text: "범위는 3.1) 절에서 다룬다. 끝났다.1) 다음",
            notes: [.init(marker: "1", text: "각주")])])
        XCTAssertTrue(text.contains("\n\n범위는 3.1) 절에서 다룬다. 끝났다.[^1] 다음\n\n"))
        assertDefinitionsReferencedOnce(text)
    }

    func testRetainedTopParagraphEscapesMarkdownHeadingPrefix() {
        XCTAssertEqual(MarkdownDocumentRenderer.render(pages: [page(1, candidates: ["# 본문"])]),
                       "[PDF p. 1]\n\n\\# 본문\n")
    }

    private func page(_ number: Int, printed: Int? = nil, candidates: [String] = [], text: String? = nil,
                      blocks: [MarkdownPage.Block] = [], notes: [MarkdownPage.Footnote] = []) -> MarkdownPage {
        MarkdownPage(pdfPage: number, printedPage: printed, topCandidates: candidates.map { .init(kind: .paragraph, text: $0) },
                     blocks: blocks + (text.map { [.init(kind: .paragraph, text: $0)] } ?? []), footnotes: notes)
    }

    private func assertDefinitionsReferencedOnce(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let parts = text.components(separatedBy: "<!-- footnotes -->")
        guard parts.count == 2 else {
            XCTFail("Missing footnote separator", file: file, line: line)
            return
        }
        let expression = try! NSRegularExpression(pattern: "(?m)^\\[\\^([^]]+)\\]:")
        let definitions = parts[1]
        let labels = expression.matches(in: definitions, range: NSRange(definitions.startIndex..., in: definitions)).map {
            String(definitions[Range($0.range(at: 1), in: definitions)!])
        }
        XCTAssertEqual(Set(labels).count, labels.count, file: file, line: line)
        for label in labels {
            XCTAssertEqual(parts[0].components(separatedBy: "[^\(label)]").count - 1, 1, label, file: file, line: line)
        }
    }
}
