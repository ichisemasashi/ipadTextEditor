import Foundation

/// コード用の汎用レキサ。コメント・文字列は 1 パスの走査で正確に判定し、
/// キーワード・数値はその外側にだけ正規表現でマッチさせる。
enum CodeHighlighter {

    enum Kind {
        case comment
        case string
        case keyword
        case number
    }

    struct Token: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private static let numberRegex = try! NSRegularExpression(
        pattern: #"\b0x[0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#
    )

    private static var keywordRegexCache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    static func tokens(in text: String, language: LanguageDefinition) -> [Token] {
        let units = Array(text.utf16)
        let n = units.count
        var tokens: [Token] = []
        /// コメント・文字列で消費済みの範囲(位置順)
        var covered: [NSRange] = []

        let newline: UInt16 = 10
        let backslash: UInt16 = 92
        let lineComment = language.lineComment.map { Array($0.utf16) }
        let blockStart = language.blockCommentStart.map { Array($0.utf16) }
        let blockEnd = language.blockCommentEnd.map { Array($0.utf16) }
        let multiDelimiters = language.multilineStringDelimiters.map { Array($0.utf16) }
        let quoteChars = Set(language.stringDelimiters.compactMap { String($0).utf16.first })

        func matches(_ marker: [UInt16], at index: Int) -> Bool {
            guard index + marker.count <= n else { return false }
            for (offset, unit) in marker.enumerated() where units[index + offset] != unit {
                return false
            }
            return true
        }

        func emit(_ start: Int, _ end: Int, _ kind: Kind) {
            let range = NSRange(location: start, length: end - start)
            tokens.append(Token(range: range, kind: kind))
            covered.append(range)
        }

        var i = 0
        scan: while i < n {
            // ブロックコメント
            if let start = blockStart, let end = blockEnd, matches(start, at: i) {
                var j = i + start.count
                while j < n && !matches(end, at: j) { j += 1 }
                let stop = j < n ? j + end.count : n
                emit(i, stop, .comment)
                i = stop
                continue
            }
            // 行コメント
            if let marker = lineComment, matches(marker, at: i) {
                var j = i
                while j < n && units[j] != newline { j += 1 }
                emit(i, j, .comment)
                i = j
                continue
            }
            // 複数行文字列("""など。通常のクォートより先に判定)
            for delimiter in multiDelimiters where matches(delimiter, at: i) {
                var j = i + delimiter.count
                while j < n && !matches(delimiter, at: j) {
                    j += (units[j] == backslash) ? 2 : 1
                }
                let stop = j < n ? min(n, j + delimiter.count) : n
                emit(i, stop, .string)
                i = stop
                continue scan
            }
            // 1 行文字列(閉じないまま行末に達したらそこで打ち切る)
            if quoteChars.contains(units[i]) {
                let quote = units[i]
                var j = i + 1
                while j < n && units[j] != quote && units[j] != newline {
                    j += (units[j] == backslash) ? 2 : 1
                }
                let stop = (j < n && units[j] == quote) ? j + 1 : min(j, n)
                emit(i, stop, .string)
                i = stop
                continue
            }
            i += 1
        }

        // コメント・文字列の外側にだけキーワードと数値をマッチさせる
        func isCovered(_ range: NSRange) -> Bool {
            var low = 0
            var high = covered.count - 1
            while low <= high {
                let mid = (low + high) / 2
                let candidate = covered[mid]
                if NSIntersectionRange(candidate, range).length > 0 { return true }
                if candidate.location < range.location {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return false
        }

        let fullRange = NSRange(location: 0, length: n)
        if !language.keywords.isEmpty, let regex = keywordRegex(for: language) {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match, !isCovered(match.range) else { return }
                tokens.append(Token(range: match.range, kind: .keyword))
            }
        }
        numberRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, !isCovered(match.range) else { return }
            tokens.append(Token(range: match.range, kind: .number))
        }

        return tokens
    }

    private static func keywordRegex(for language: LanguageDefinition) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = keywordRegexCache[language.name] { return cached }

        let alternation = language.keywords
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let regex = try? NSRegularExpression(
            pattern: #"\b(?:"# + alternation + #")\b"#,
            options: language.caseInsensitiveKeywords ? [.caseInsensitive] : []
        )
        keywordRegexCache[language.name] = regex
        return regex
    }
}
