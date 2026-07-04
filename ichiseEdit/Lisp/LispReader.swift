import Foundation

/// S 式のリーダ(字句解析+構文解析)。
/// シンボルは ISLISP の慣習に合わせて小文字に正規化する(文字列は保持)。
struct LispReader {
    private let scalars: [Character]
    private var position = 0

    init(_ source: String) {
        self.scalars = Array(source)
    }

    /// ソース全体を読み、トップレベルの式の配列を返す
    static func readAll(_ source: String) throws -> [LispValue] {
        var reader = LispReader(source)
        var forms: [LispValue] = []
        while let form = try reader.readForm() {
            forms.append(form)
        }
        return forms
    }

    // MARK: - 構文解析

    mutating func readForm() throws -> LispValue? {
        skipWhitespaceAndComments()
        guard position < scalars.count else { return nil }
        let c = scalars[position]

        switch c {
        case "(":
            position += 1
            return try readList()
        case ")":
            throw LispError("対応しない ')' があります")
        case "'":
            position += 1
            return try wrapNext(in: "quote")
        case "`":
            position += 1
            return try wrapNext(in: "quasiquote")
        case ",":
            position += 1
            if position < scalars.count, scalars[position] == "@" {
                position += 1
                return try wrapNext(in: "unquote-splicing")
            }
            return try wrapNext(in: "unquote")
        case "\"":
            position += 1
            return try readString()
        case "#":
            return try readHash()
        default:
            return try readAtom()
        }
    }

    private mutating func wrapNext(in symbol: String) throws -> LispValue {
        guard let form = try readForm() else {
            throw LispError("'\(symbol)' の後に式がありません")
        }
        return .list([.symbol(symbol), form])
    }

    private mutating func readList() throws -> LispValue {
        var items: [LispValue] = []
        var dottedTail: LispValue?

        while true {
            skipWhitespaceAndComments()
            guard position < scalars.count else {
                throw LispError("')' が閉じられていません")
            }
            if scalars[position] == ")" {
                position += 1
                break
            }
            // ドット対
            if scalars[position] == ".",
               position + 1 < scalars.count,
               isDelimiter(scalars[position + 1]) {
                position += 1
                guard let tail = try readForm() else {
                    throw LispError("'.' の後に式がありません")
                }
                dottedTail = tail
                skipWhitespaceAndComments()
                guard position < scalars.count, scalars[position] == ")" else {
                    throw LispError("ドット対の後は ')' が必要です")
                }
                position += 1
                break
            }
            guard let form = try readForm() else {
                throw LispError("')' が閉じられていません")
            }
            items.append(form)
        }

        var result = dottedTail ?? .nilValue
        for item in items.reversed() {
            result = .cons(item, result)
        }
        return result
    }

    private mutating func readString() throws -> LispValue {
        var result = ""
        while position < scalars.count {
            let c = scalars[position]
            position += 1
            if c == "\"" {
                return .string(result)
            }
            if c == "\\" {
                guard position < scalars.count else { break }
                let next = scalars[position]
                position += 1
                switch next {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: result.append(next)
                }
            } else {
                result.append(c)
            }
        }
        throw LispError("文字列が閉じられていません")
    }

    private mutating func readHash() throws -> LispValue {
        position += 1 // '#'
        guard position < scalars.count else {
            throw LispError("'#' の後に何もありません")
        }
        let c = scalars[position]
        switch c {
        case "\\":
            position += 1
            return try readCharacter()
        case "(":
            position += 1
            guard let items = try readList().toArray() else {
                throw LispError("ベクタ表記が不正です")
            }
            return .vector(items)
        case "'":
            position += 1
            return try wrapNext(in: "function")
        default:
            throw LispError("未対応の '#' 構文です: #\(c)")
        }
    }

    private mutating func readCharacter() throws -> LispValue {
        guard position < scalars.count else {
            throw LispError("'#\\' の後に文字がありません")
        }
        // 名前付き文字(newline / space / tab)
        var name = ""
        var lookahead = position
        while lookahead < scalars.count, scalars[lookahead].isLetter {
            name.append(scalars[lookahead])
            lookahead += 1
        }
        switch name.lowercased() {
        case "newline":
            position = lookahead
            return .character("\n")
        case "space":
            position = lookahead
            return .character(" ")
        case "tab":
            position = lookahead
            return .character("\t")
        default:
            let c = scalars[position]
            position += 1
            return .character(c)
        }
    }

    private mutating func readAtom() throws -> LispValue {
        var token = ""
        while position < scalars.count, !isDelimiter(scalars[position]) {
            token.append(scalars[position])
            position += 1
        }
        guard !token.isEmpty else {
            throw LispError("空のトークンです")
        }

        if let n = Int(token) {
            return .integer(n)
        }
        // "1." のような表記や単独の記号を数値と誤認しないための簡易判定
        if token.contains(where: { $0.isNumber }), let d = Double(token),
           token.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil {
            return .double(d)
        }

        let lowered = token.lowercased()
        switch lowered {
        case "nil": return .nilValue
        case "t": return .t
        default: return .symbol(lowered)
        }
    }

    // MARK: - 字句ユーティリティ

    private func isDelimiter(_ c: Character) -> Bool {
        c.isWhitespace || c == "(" || c == ")" || c == "\"" || c == ";" || c == "'" || c == "`" || c == ","
    }

    private mutating func skipWhitespaceAndComments() {
        while position < scalars.count {
            let c = scalars[position]
            if c.isWhitespace {
                position += 1
            } else if c == ";" {
                while position < scalars.count, scalars[position] != "\n" {
                    position += 1
                }
            } else if c == "#", position + 1 < scalars.count, scalars[position + 1] == "|" {
                position += 2
                while position + 1 < scalars.count,
                      !(scalars[position] == "|" && scalars[position + 1] == "#") {
                    position += 1
                }
                position = min(position + 2, scalars.count)
            } else {
                break
            }
        }
    }
}
