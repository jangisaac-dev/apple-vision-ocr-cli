import Foundation

struct MarkdownPage: Codable, Equatable {
    var pdfPage: Int
    var printedPage: Int?
    var topCandidates: [Block]
    var blocks: [Block]
    var footnotes: [Footnote]

    struct Block: Codable, Equatable {
        enum Kind: String, Codable {
            case title, heading, paragraph, table
        }

        var kind: Kind
        var text: String
    }

    struct Footnote: Codable, Equatable {
        var marker: String?
        var text: String
    }
}

enum MarkdownTable {
    struct Cell: Equatable {
        let rows: ClosedRange<Int>
        let columns: ClosedRange<Int>
        let text: String
    }

    static func render(cells: [Cell]) -> String {
        guard let lastRow = cells.map({ $0.rows.upperBound }).max(),
              let lastColumn = cells.map({ $0.columns.upperBound }).max() else {
            return ""
        }
        var grid = Array(repeating: Array(repeating: "", count: lastColumn + 1), count: lastRow + 1)
        for cell in cells {
            grid[cell.rows.lowerBound][cell.columns.lowerBound] = cell.text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines = grid.map { "| " + $0.joined(separator: " | ") + " |" }
        lines.insert("| " + Array(repeating: "---", count: lastColumn + 1).joined(separator: " | ") + " |", at: 1)
        return lines.joined(separator: "\n")
    }
}

enum MarkdownDocumentRenderer {
    static func render(pages: [MarkdownPage]) -> String {
        let pages = pages.sorted { $0.pdfPage < $1.pdfPage }
        let originalNumbers = Dictionary(uniqueKeysWithValues: pages.compactMap { page in
            page.printedPage.map { (page.pdfPage, $0) }
        })
        var correctedNumbers = originalNumbers
        for page in pages {
            var counts: [Int: Int] = [:]
            for neighbor in (page.pdfPage - 2)...(page.pdfPage + 2) where neighbor != page.pdfPage {
                if let printed = originalNumbers[neighbor] { counts[printed - neighbor, default: 0] += 1 }
            }
            if let highest = counts.values.max(), highest >= 2 {
                let winners = counts.filter { $0.value == highest }
                if winners.count == 1, let offset = winners.first?.key {
                    correctedNumbers[page.pdfPage] = page.pdfPage + offset
                }
            }
        }
        var definitions: [(label: String, text: String)] = []
        var usedLabels: Set<String> = []
        var lastDefinitionByPage: [Int: Int] = [:]
        var renderedPages: [String] = []

        for page in pages {
            var printedPage = correctedNumbers[page.pdfPage]
            let expectedNumbers = Set([
                correctedNumbers[page.pdfPage],
                correctedNumbers[page.pdfPage - 1].map { $0 + 1 },
                correctedNumbers[page.pdfPage + 1].map { $0 - 1 }
            ].compactMap { $0 })
            let candidates = page.topCandidates.filter { candidate in
                let numbers = candidate.text.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
                guard let number = numbers.compactMap({ Int($0) }).first(where: { expectedNumbers.contains($0) }) else {
                    return true
                }
                if printedPage == nil {
                    printedPage = number
                }
                return false
            }
            var marker = printedPage.map { "[p. \($0)]" } ?? "[PDF p. \(page.pdfPage)]"
            var blocks: [MarkdownPage.Block] = []
            for candidate in candidates {
                if candidate.kind == .paragraph, blocks.last?.kind == .paragraph {
                    blocks[blocks.count - 1].text += "\n" + candidate.text
                } else { blocks.append(candidate) }
            }
            blocks.append(contentsOf: page.blocks)

            for (index, footnote) in page.footnotes.enumerated() {
                let ordinal = index + 1
                if footnote.marker == nil, index == 0,
                   let previous = lastDefinitionByPage[page.pdfPage - 1] {
                    definitions[previous].text += "\n" + footnote.text
                    lastDefinitionByPage[page.pdfPage] = previous
                    continue
                }

                let label: String
                let numeric = footnote.marker.map { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } } ?? false
                if numeric, let number = footnote.marker {
                    if !usedLabels.contains(number) {
                        label = number
                    } else {
                        let base = "\(number)-p\(page.pdfPage)"
                        var unique = base
                        var suffix = 2
                        while usedLabels.contains(unique) {
                            unique = "\(base)-\(suffix)"
                            suffix += 1
                        }
                        label = unique
                    }
                } else {
                    label = "p\(page.pdfPage)-\(footnote.marker == nil ? "u" : "s")\(ordinal)"
                }
                usedLabels.insert(label)
                lastDefinitionByPage[page.pdfPage] = definitions.count
                definitions.append((label, footnote.text))
                if !numeric || !replaceReference(number: footnote.marker!, label: label, blocks: &blocks) {
                    marker += " [^\(label)]"
                }
            }

            var parts = [marker]
            parts.append(contentsOf: blocks.map { block in
                switch block.kind {
                case .title: return "# " + block.text
                case .heading: return "## " + block.text
                case .paragraph, .table: return block.text
                }
            })
            renderedPages.append(parts.joined(separator: "\n\n"))
        }

        var result = renderedPages.joined(separator: "\n\n")
        if !definitions.isEmpty {
            result += "\n\n<!-- footnotes -->\n\n" + definitions.map { definition in
                "[^\(definition.label)]: " + definition.text.replacingOccurrences(of: "\n", with: "\n    ")
            }.joined(separator: "\n")
        }
        while result.last == "\n" {
            result.removeLast()
        }
        return result + "\n"
    }

    private static func replaceReference(number: String, label: String, blocks: inout [MarkdownPage.Block]) -> Bool {
        let pattern = "(?<=[가-힣A-Za-z一-鿿.,?!\"”’')」』\\]])" + NSRegularExpression.escapedPattern(for: number)
            + "\\)(?=$|[\\s.,;:!?\"”’')」』\\]])"
        let expression = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        for index in blocks.indices where blocks[index].kind == .paragraph {
            let text = blocks[index].text
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let prefix = text[..<range.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
                guard prefix.filter({ $0 == "(" }).count <= prefix.filter({ $0 == ")" }).count else { continue }
                blocks[index].text.replaceSubrange(range, with: "[^\(label)]")
                return true
            }
        }
        return false
    }
}
