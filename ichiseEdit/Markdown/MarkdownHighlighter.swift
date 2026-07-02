import Foundation

/// Markdown の軽量トークナイザ。行単位で走査し、装飾すべき範囲と種類を返す。
/// フル AST は不要(エディタ内の色付けが目的)なので正規表現ベースで実装する。
enum MarkdownHighlighter {

    enum Kind {
        case heading
        case listMarker
        case blockquote
        case codeBlock
        case codeSpan
        case bold
        case italic
        case linkText
        case linkURL
    }

    struct Token: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private static let heading = try! NSRegularExpression(pattern: #"^#{1,6}[ \t].*$"#)
    private static let listMarker = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+\.)[ \t]"#)
    private static let bold = try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#)
    // 前後の除外は ASCII 英数字のみ(\w は日本語にもマッチしてしまうため使わない)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![*A-Za-z0-9])\*[^*\n]+\*(?!\*)|(?<![_A-Za-z0-9])_[^_\n]+_(?![A-Za-z0-9_])"#)
    private static let codeSpan = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    static func tokens(in text: String) -> [Token] {
        let ns = text as NSString
        var tokens: [Token] = []
        var insideFence = false
        var location = 0

        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            defer { location = NSMaxRange(lineRange) }
            let line = ns.substring(with: lineRange)
            let lineNS = line as NSString
            let fullLine = NSRange(location: 0, length: lineNS.length)

            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                tokens.append(Token(range: lineRange, kind: .codeBlock))
                insideFence.toggle()
                continue
            }
            if insideFence {
                tokens.append(Token(range: lineRange, kind: .codeBlock))
                continue
            }

            func absolute(_ r: NSRange) -> NSRange {
                NSRange(location: lineRange.location + r.location, length: r.length)
            }

            if let match = heading.firstMatch(in: line, range: fullLine) {
                tokens.append(Token(range: absolute(match.range), kind: .heading))
                continue
            }
            if line.hasPrefix(">") {
                tokens.append(Token(range: lineRange, kind: .blockquote))
                continue
            }
            if let match = listMarker.firstMatch(in: line, range: fullLine) {
                tokens.append(Token(range: absolute(match.range), kind: .listMarker))
            }

            // インライン装飾。コードスパンを先に確定し、その内側は他の装飾を適用しない
            var codeSpanRanges: [NSRange] = []
            codeSpan.enumerateMatches(in: line, range: fullLine) { match, _, _ in
                guard let match else { return }
                codeSpanRanges.append(match.range)
                tokens.append(Token(range: absolute(match.range), kind: .codeSpan))
            }
            func overlapsCodeSpan(_ r: NSRange) -> Bool {
                codeSpanRanges.contains { NSIntersectionRange($0, r).length > 0 }
            }

            bold.enumerateMatches(in: line, range: fullLine) { match, _, _ in
                guard let match, !overlapsCodeSpan(match.range) else { return }
                tokens.append(Token(range: absolute(match.range), kind: .bold))
            }
            italic.enumerateMatches(in: line, range: fullLine) { match, _, _ in
                guard let match, !overlapsCodeSpan(match.range) else { return }
                tokens.append(Token(range: absolute(match.range), kind: .italic))
            }
            link.enumerateMatches(in: line, range: fullLine) { match, _, _ in
                guard let match, !overlapsCodeSpan(match.range) else { return }
                tokens.append(Token(range: absolute(match.range(at: 1)), kind: .linkText))
                tokens.append(Token(range: absolute(match.range(at: 2)), kind: .linkURL))
            }
        }
        return tokens
    }
}
