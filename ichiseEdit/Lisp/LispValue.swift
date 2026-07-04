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
    // ILOS(オブジェクトシステム)
    case classObject(LispClass)
    case instance(LispInstance)
    case generic(LispGeneric)

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
    /// スロットアクセサなど、本体が Swift 実装のメソッドで使う(通常の関数は nil)
    let builtinBody: LispBuiltin?

    init(
        name: String?,
        parameters: [String],
        restParameter: String?,
        body: [LispValue],
        closure: LispEnvironment,
        isMacro: Bool = false,
        builtinBody: LispBuiltin? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.restParameter = restParameter
        self.body = body
        self.closure = closure
        self.isMacro = isMacro
        self.builtinBody = builtinBody
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

// MARK: - ILOS(オブジェクトシステム)

/// スロット定義
struct LispSlotSpec {
    let name: String
    let initform: LispValue?      // 初期値式(未指定なら nil)
    let initarg: String?          // create 時のキーワード引数名
    let accessor: String?         // 読み書きアクセサ関数名
    let reader: String?           // 読み取り専用アクセサ関数名
}

/// クラス(defclass)。多重継承をサポートする。
final class LispClass {
    let name: String
    let directSuperclasses: [LispClass]
    let directSlots: [LispSlotSpec]
    /// C3 線形化によるクラス優先順位リスト(自分自身から祖先順)
    private(set) var precedenceList: [LispClass] = []
    /// 継承を含めた全スロット(先祖優先で重複排除)
    private(set) var allSlots: [LispSlotSpec] = []

    init(name: String, directSuperclasses: [LispClass], directSlots: [LispSlotSpec]) {
        self.name = name
        self.directSuperclasses = directSuperclasses
        self.directSlots = directSlots
    }

    func finalize() throws {
        precedenceList = try LispClass.c3Linearize(self)
        // スロットは優先順位の低い(祖先)側から集め、派生クラスの定義で上書きする
        var merged: [String: LispSlotSpec] = [:]
        var order: [String] = []
        for cls in precedenceList.reversed() {
            for slot in cls.directSlots {
                if merged[slot.name] == nil { order.append(slot.name) }
                merged[slot.name] = slot
            }
        }
        allSlots = order.compactMap { merged[$0] }
    }

    func isSubclass(of other: LispClass) -> Bool {
        precedenceList.contains { $0 === other }
    }

    /// C3 線形化(Python/Dylan と同じ単調な多重継承解決)
    static func c3Linearize(_ cls: LispClass) throws -> [LispClass] {
        if cls.directSuperclasses.isEmpty {
            return [cls]
        }
        var sequences: [[LispClass]] = try cls.directSuperclasses.map { try c3Linearize($0) }
        sequences.append(cls.directSuperclasses)
        var result: [LispClass] = [cls]
        var lists = sequences

        while true {
            lists = lists.filter { !$0.isEmpty }
            if lists.isEmpty { break }
            var candidate: LispClass?
            for list in lists {
                let head = list[0]
                let appearsInTail = lists.contains { other in
                    other.dropFirst().contains { $0 === head }
                }
                if !appearsInTail {
                    candidate = head
                    break
                }
            }
            guard let next = candidate else {
                throw LispError("クラス \(cls.name) の継承関係を解決できません(継承が矛盾しています)")
            }
            result.append(next)
            lists = lists.map { list in
                list.first === next ? Array(list.dropFirst()) : list
            }
        }
        return result
    }
}

/// インスタンス(create で生成)
final class LispInstance {
    let isa: LispClass
    var slots: [String: LispValue]

    init(isa: LispClass, slots: [String: LispValue]) {
        self.isa = isa
        self.slots = slots
    }
}

/// 総称関数(defgeneric)に属する 1 つのメソッド
struct LispMethod {
    enum Qualifier {
        case primary
        case before
        case after
        case around
    }

    let qualifier: Qualifier
    let specializer: LispClass   // 第 1 引数に要求するクラス
    let function: LispFunction   // 本体(call-next-method を閉包に持つ)
}

/// 総称関数(defgeneric)。メソッドをクラスで単一ディスパッチする。
final class LispGeneric {
    let name: String
    private(set) var methods: [LispMethod] = []

    init(name: String) {
        self.name = name
    }

    func addMethod(_ method: LispMethod) {
        // 同じ修飾子・同じスペシャライザの既存メソッドは置き換える
        methods.removeAll {
            $0.qualifier == method.qualifier && $0.specializer === method.specializer
        }
        methods.append(method)
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
        case (.classObject(let x), .classObject(let y)):
            return x === y
        case (.instance(let x), .instance(let y)):
            return x === y
        case (.generic(let x), .generic(let y)):
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
        case .classObject(let cls):
            return "#<class \(cls.name)>"
        case .instance(let obj):
            return "#<instance of \(obj.isa.name)>"
        case .generic(let g):
            return "#<generic \(g.name)>"
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
