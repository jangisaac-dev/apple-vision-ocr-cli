import Foundation

struct LayoutRegion: Equatable {
    let query: Int
    let label: String
    let score: Float
    let rect: CGRect
}

struct LayoutLine: Equatable {
    let text: String
    let rect: CGRect
}

enum LayoutDecoder {
    static let labels = [
        "abstract", "algorithm", "aside_text", "chart", "content", "display_formula",
        "doc_title", "figure_title", "footer", "footer_image", "footnote", "formula_number",
        "header", "header_image", "image", "inline_formula", "number", "paragraph_title",
        "reference", "reference_content", "seal", "table", "text", "vertical_text", "vision_footnote"
    ]

    static func regions(logits: [Float], boxes: [Float], orderLogits: [Float],
                        queryCount: Int = 300, classCount: Int = 25,
                        threshold: Float = 0.4) -> [LayoutRegion] {
        precondition(queryCount >= 0 && classCount > 0 && classCount <= labels.count)
        precondition(logits.count == queryCount * classCount && boxes.count == queryCount * 4
                     && orderLogits.count == queryCount * queryCount)
        func sigmoid(_ value: Float) -> Float { 1 / (1 + exp(-value)) }
        var votes = [Float](repeating: 0, count: queryCount)
        for j in 0..<queryCount {
            for i in 0..<j { votes[j] += sigmoid(orderLogits[i * queryCount + j]) }
            for i in (j + 1)..<queryCount { votes[j] += 1 - sigmoid(orderLogits[j * queryCount + i]) }
        }
        return (0..<queryCount).sorted {
            votes[$0] == votes[$1] ? $0 < $1 : votes[$0] < votes[$1]
        }.compactMap { query in
            let start = query * classCount
            var best = 0
            for label in 1..<classCount where logits[start + label] > logits[start + best] { best = label }
            let score = sigmoid(logits[start + best])
            guard score >= threshold else { return nil }
            let box = query * 4
            let width = CGFloat(boxes[box + 2]), height = CGFloat(boxes[box + 3])
            return LayoutRegion(query: query, label: labels[best], score: score,
                                rect: CGRect(x: CGFloat(boxes[box]) - width / 2,
                                             y: CGFloat(boxes[box + 1]) - height / 2,
                                             width: width, height: height))
        }
    }
}

enum MarkdownPageAnalyzer {
    private static let discarded: Set<String> = ["header", "footer", "header_image", "footer_image", "seal"]

    static func analyze(pdfPage: Int, regions: [LayoutRegion], lines: [LayoutLine],
                        recognizeCrop: (CGRect) throws -> [LayoutLine],
                        recognizeTable: (CGRect) throws -> String?) rethrows -> MarkdownPage {
        let content = regions.indices.filter { !discarded.contains(regions[$0].label) && regions[$0].label != "number" }
        let heights = lines.map { $0.rect.height }.sorted()
        let median = heights.isEmpty ? 0 : heights[(heights.count - 1) / 2]
        var assigned = [[LayoutLine]](repeating: [], count: regions.count)
        var unassigned: [LayoutLine] = []
        for line in lines {
            let matches = regions.indices.filter {
                contains(regions[$0].rect.insetBy(dx: -0.005, dy: -0.004), centerOf: line.rect)
            }
            let chosen = matches.min { a, b in
                let aContent = content.contains(a), bContent = content.contains(b)
                if aContent != bContent { return aContent }
                let aArea = regions[a].rect.width * regions[a].rect.height
                let bArea = regions[b].rect.width * regions[b].rect.height
                return aArea == bArea ? a < b : aArea < bArea
            }
            if let chosen { assigned[chosen].append(line) } else { unassigned.append(line) }
        }
        for index in content where regions[index].label != "table" && assigned[index].isEmpty {
            guard !lines.contains(where: { contains(regions[index].rect, centerOf: $0.rect) }) else { continue }
            assigned[index] = try recognizeCrop(padded(regions[index].rect)).filter {
                median == 0 || $0.rect.height >= 0.6 * median
            }
        }
        var printedPage: Int?
        for region in regions where region.label == "number" {
            let text = try recognizeCrop(padded(region.rect)).map(\.text).joined(separator: " ")
            if printedPage == nil, let match = firstMatch("(?<![0-9])([0-9]{1,5})(?![0-9])", in: text) {
                printedPage = Int(match.1)
            }
        }
        var footnoteIndices = Set(content.filter { regions[$0].label == "footnote" })
        var corrected: Set<Int> = []
        for index in content.sorted(by: { regions[$0].rect.minY == regions[$1].rect.minY ? $0 > $1 : regions[$0].rect.minY > regions[$1].rect.minY }) {
            if regions[index].label == "footnote" { continue }
            if regions[index].label == "text", regions[index].rect.midY > 0.5,
               let first = assigned[index].first?.text,
               firstMatch("^\\s*\\(?[0-9]{1,3}\\)", in: first) != nil {
                corrected.insert(index)
            } else { break }
        }
        if content.contains(where: { !footnoteIndices.contains($0) && !corrected.contains($0) }) {
            footnoteIndices.formUnion(corrected)
        }
        let anchors = content.filter { !footnoteIndices.contains($0) }
        var topCandidates: [String] = []
        var insertions: [(anchor: Int?, lines: [LayoutLine])] = []
        let minY = content.map { regions[$0].rect.minY }.min()
        let maxY = content.map { regions[$0].rect.maxY }.max()
        for line in unassigned {
            if let minY, line.rect.midY < minY && line.rect.midY < 0.14 {
                topCandidates.append(line.text)
                continue
            }
            if let maxY, line.rect.midY > maxY && line.rect.midY > 0.86,
               median > 0 && line.rect.height >= 1.5 * median { continue }
            let anchor = anchors.filter {
                let rect = regions[$0].rect
                return rect.maxY <= line.rect.midY && min(rect.maxX, line.rect.maxX) > max(rect.minX, line.rect.minX)
            }.max {
                let a = regions[$0].rect.maxY, b = regions[$1].rect.maxY
                return a == b ? $0 < $1 : a < b
            }
            if let last = insertions.indices.last, insertions[last].anchor == anchor {
                insertions[last].lines.append(line)
            } else { insertions.append((anchor, [line])) }
        }
        var blocks: [MarkdownPage.Block] = []
        func appendInsertions(after anchor: Int?) {
            for group in insertions where group.anchor == anchor {
                let text = paragraph(group.lines)
                if !text.isEmpty { blocks.append(.init(kind: .paragraph, text: text)) }
            }
        }
        appendInsertions(after: nil)
        for index in anchors {
            let region = regions[index]
            let text: String
            let kind: MarkdownPage.Block.Kind
            if region.label == "table", let table = try recognizeTable(padded(region.rect)),
               !table.isEmpty {
                text = table
                kind = .table
            } else if region.label == "doc_title" || region.label == "paragraph_title" {
                text = assigned[index].map(\.text).joined(separator: " ")
                kind = region.label == "doc_title" ? .title : .heading
            } else {
                text = paragraph(assigned[index])
                kind = .paragraph
            }
            if !text.isEmpty {
                blocks.append(.init(kind: kind, text: text))
            }
            appendInsertions(after: index)
        }
        let footnotes: [MarkdownPage.Footnote] = footnoteIndices.sorted {
            regions[$0].rect.minY == regions[$1].rect.minY ? $0 < $1 : regions[$0].rect.minY < regions[$1].rect.minY
        }.compactMap { index in
            let text = assigned[index].map(\.text).joined(separator: "\n").replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
            guard !text.isEmpty else { return nil }
            for pattern in ["^\\(([0-9]{1,3})\\)\\s*", "^([0-9]{1,3})\\)\\s*", "^([0-9]{1,3})\\s+", "^([*†‡])\\s*"] {
                if let match = firstMatch(pattern, in: text) {
                    let remainder = String(text[match.0.upperBound...])
                    return remainder.isEmpty ? nil : .init(marker: match.1, text: remainder)
                }
            }
            return .init(marker: nil, text: text)
        }
        return MarkdownPage(pdfPage: pdfPage, printedPage: printedPage, topCandidates: topCandidates,
                            blocks: blocks, footnotes: footnotes)
    }

    private static func contains(_ rect: CGRect, centerOf line: CGRect) -> Bool {
        line.midX >= rect.minX && line.midX <= rect.maxX && line.midY >= rect.minY && line.midY <= rect.maxY
    }

    private static func padded(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -0.01, dy: -0.01).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func paragraph(_ lines: [LayoutLine]) -> String {
        lines.map(\.text).joined(separator: "\n").components(separatedBy: "\n")
            .map { $0.hasPrefix("#") ? "\\" + $0 : $0 }.joined(separator: "\n")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (Range<String.Index>, String)? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let capture = match.numberOfRanges > 1 ? String(text[Range(match.range(at: 1), in: text)!]) : ""
        return (range, capture)
    }
}
