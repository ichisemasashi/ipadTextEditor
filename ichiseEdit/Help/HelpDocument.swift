import Foundation

/// ヘルプ用の軽量 Markdown パーサ。
/// ブロック(見出し・段落・コード・リスト・表・区切り線)は自前で分割し、
/// インライン装飾(**太字** `コード` [リンク])は AttributedString に任せる。
/// マニュアルは表を多用するため、Foundation では描けない表もここで扱う。
struct HelpDocument {

    enum Block: Identifiable {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case codeBlock(String)
        case listItem(marker: String, text: AttributedString)
        case table(headers: [AttributedString], rows: [[AttributedString]])
        case divider

        var id: String {
            switch self {
            case .heading(_, let t): return "h:\(t.characters.count):\(String(t.characters.prefix(8)))"
            case .paragraph(let t): return "p:\(t.characters.count):\(String(t.characters.prefix(8)))"
            case .codeBlock(let c): return "c:\(c.count):\(c.prefix(8))"
            case .listItem(_, let t): return "l:\(t.characters.count):\(String(t.characters.prefix(8)))"
            case .table(let h, let r): return "t:\(h.count):\(r.count)"
            case .divider: return "hr"
            }
        }
    }

    let blocks: [IdentifiedBlock]

    /// ForEach 用に安定 ID を振ったブロック
    struct IdentifiedBlock: Identifiable {
        let id: Int
        let block: Block
    }

    init(markdown: String) {
        self.blocks = HelpDocument.parse(markdown).enumerated().map {
            IdentifiedBlock(id: $0.offset, block: $0.element)
        }
    }

    static func parse(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0

        func inline(_ text: String) -> AttributedString {
            (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(text)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // コードフェンス ```
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // 閉じフェンス
                blocks.append(.codeBlock(code.joined(separator: "\n")))
                continue
            }

            // 区切り線 --- / ***
            if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider)
                index += 1
                continue
            }

            // 見出し #
            if let level = headingLevel(trimmed) {
                let content = String(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                blocks.append(.heading(level: level, text: inline(content)))
                index += 1
                continue
            }

            // 表(| で始まり、次行が区切り行)
            if trimmed.hasPrefix("|"), index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                let headers = tableCells(trimmed).map { inline($0) }
                index += 2 // ヘッダ行 + 区切り行
                var rows: [[AttributedString]] = []
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[index]).map { inline($0) })
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // リスト項目 - / * / 数字.
            if let (marker, rest) = listMarker(trimmed) {
                blocks.append(.listItem(marker: marker, text: inline(rest)))
                index += 1
                continue
            }

            // 段落(連続する非空・非特殊行をまとめる)
            var paragraph = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || headingLevel(next) != nil || next.hasPrefix("```")
                    || next.hasPrefix("|") || listMarker(next) != nil
                    || next == "---" || next == "***" {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
        }

        return blocks
    }

    // MARK: - 行の判定

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6,
              line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listMarker(_ line: String) -> (marker: String, rest: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ("•", String(line.dropFirst(2)))
        }
        // 1. 2. ... の順序付きリスト
        let prefix = line.prefix { $0.isNumber }
        if !prefix.isEmpty, line.dropFirst(prefix.count).hasPrefix(". ") {
            return ("\(prefix).", String(line.dropFirst(prefix.count + 2)))
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        // |---|:--:|--- のような区切り行(- と : と | と空白のみ)
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
            && trimmed.contains("-")
    }

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // 先頭と末尾の空セル(| で囲まれることによる)を落とす
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
}
