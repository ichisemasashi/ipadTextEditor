import Foundation

/// ISLISP の値。nil は空リストかつ偽を兼ねる(ISLISP の慣習どおり)。
indirect enum LispValue {
    case nilValue
    case t
    case integer(Int)
    case double(Double)
    case string(String)
    case symbol(String)
    case character(Character)
    case cons(LispValue, LispValue)
    case vector([LispValue])
    case function(LispFunction)
    case builtin(LispBuiltin)

    var isNil: Bool {
        if case .nilValue = self { return true }
        return false
    }

    var isTruthy: Bool { !isNil }

    /// Swift 配列 → リスト
    static func list(_ items: [LispValue]) -> LispValue {
        var result = LispValue.nilValue
        for item in items.reversed() {
            result = .cons(item, result)
        }
        return result
    }

    /// リスト → Swift 配列(真リストでなければ nil)
    func toArray() -> [LispValue]? {
        var items: [LispValue] = []
        var current = self
        while true {
            switch current {
            case .nilValue:
                return items
            case .cons(let head, let tail):
                items.append(head)
                current = tail
            default:
                return nil
            }
        }
    }
}

/// ユーザー定義関数・マクロ(lambda / defun / defmacro)
final class LispFunction {
    let name: String?
    let parameters: [String]
    let restParameter: String?
    let body: [LispValue]
    let closure: LispEnvironment
    let isMacro: Bool

    init(
        name: String?,
        parameters: [String],
        restParameter: String?,
        body: [LispValue],
        closure: LispEnvironment,
        isMacro: Bool = false
    ) {
        self.name = name
        self.parameters = parameters
        self.restParameter = restParameter
        self.body = body
        self.closure = closure
        self.isMacro = isMacro
    }
}

/// 組み込み関数
final class LispBuiltin {
    let name: String
    let body: ([LispValue], LispInterpreter) throws -> LispValue

    init(_ name: String, _ body: @escaping ([LispValue], LispInterpreter) throws -> LispValue) {
        self.name = name
        self.body = body
    }
}

// MARK: - 等値判定

enum LispEquality {
    /// eql: シンボル・数値・文字の同値、コンスは同一性
    static func eql(_ a: LispValue, _ b: LispValue) -> Bool {
        switch (a, b) {
        case (.nilValue, .nilValue), (.t, .t):
            return true
        case (.integer(let x), .integer(let y)):
            return x == y
        case (.double(let x), .double(let y)):
            return x == y
        case (.string(let x), .string(let y)):
            // ISLISP の eql は文字列では同一性だが、実装簡略化のため値比較とする
            return x == y
        case (.symbol(let x), .symbol(let y)):
            return x == y
        case (.character(let x), .character(let y)):
            return x == y
        case (.function(let x), .function(let y)):
            return x === y
        case (.builtin(let x), .builtin(let y)):
            return x === y
        default:
            return false
        }
    }

    /// equal: 構造の再帰的な同値
    static func equal(_ a: LispValue, _ b: LispValue) -> Bool {
        switch (a, b) {
        case (.cons(let ah, let at), .cons(let bh, let bt)):
            return equal(ah, bh) && equal(at, bt)
        case (.vector(let x), .vector(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { equal($0, $1) }
        default:
            return eql(a, b)
        }
    }
}

// MARK: - 表示

extension LispValue {
    /// REPL などに表示する文字列表現
    func printed() -> String {
        switch self {
        case .nilValue:
            return "nil"
        case .t:
            return "t"
        case .integer(let n):
            return String(n)
        case .double(let d):
            return d == d.rounded() && abs(d) < 1e15
                ? String(format: "%.1f", d)
                : String(d)
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case .symbol(let name):
            return name
        case .character(let c):
            switch c {
            case " ": return "#\\space"
            case "\n": return "#\\newline"
            case "\t": return "#\\tab"
            default: return "#\\\(c)"
            }
        case .cons:
            var parts: [String] = []
            var current = self
            while case .cons(let head, let tail) = current {
                parts.append(head.printed())
                current = tail
            }
            if current.isNil {
                return "(" + parts.joined(separator: " ") + ")"
            }
            return "(" + parts.joined(separator: " ") + " . " + current.printed() + ")"
        case .vector(let items):
            return "#(" + items.map { $0.printed() }.joined(separator: " ") + ")"
        case .function(let fn):
            return "#<function \(fn.name ?? "lambda")>"
        case .builtin(let builtin):
            return "#<builtin \(builtin.name)>"
        }
    }

    /// format ~A 用: 文字列・文字を装飾なしで表示
    func displayed() -> String {
        switch self {
        case .string(let s):
            return s
        case .character(let c):
            return String(c)
        case .cons:
            var parts: [String] = []
            var current = self
            while case .cons(let head, let tail) = current {
                parts.append(head.displayed())
                current = tail
            }
            if current.isNil {
                return "(" + parts.joined(separator: " ") + ")"
            }
            return "(" + parts.joined(separator: " ") + " . " + current.displayed() + ")"
        default:
            return printed()
        }
    }
}
