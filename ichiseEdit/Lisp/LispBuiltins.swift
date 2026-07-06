import Foundation

/// 組み込み関数の定義と登録。
enum LispBuiltins {

    static func install(into interpreter: LispInterpreter) {
        let globals = interpreter.globals

        func define(_ name: String, _ body: @escaping ([LispValue], LispInterpreter) throws -> LispValue) {
            globals.define(name, .builtin(LispBuiltin(name, body)))
        }

        // MARK: 数値

        define("+") { args, _ in
            try args.reduce(.integer(0)) { try numericAdd($0, $1) }
        }
        define("-") { args, _ in
            guard let first = args.first else { throw LispError("-: 引数がありません") }
            if args.count == 1 { return try numericSub(.integer(0), first) }
            return try args.dropFirst().reduce(first) { try numericSub($0, $1) }
        }
        define("*") { args, _ in
            try args.reduce(.integer(1)) { try numericMul($0, $1) }
        }
        define("/") { args, _ in
            guard let first = args.first, args.count >= 2 else {
                throw LispError("/: 引数は2つ以上必要です")
            }
            return try args.dropFirst().reduce(first) { try numericDiv($0, $1) }
        }
        define("mod") { args, _ in
            let (a, b) = try twoIntegers(args, "mod")
            guard b != 0 else { throw LispError("mod: 0 で割ることはできません") }
            let r = a % b
            return .integer((r != 0 && (r < 0) != (b < 0)) ? r + b : r)
        }
        define("rem") { args, _ in
            let (a, b) = try twoIntegers(args, "rem")
            guard b != 0 else { throw LispError("rem: 0 で割ることはできません") }
            return .integer(a % b)
        }
        define("abs") { args, _ in
            switch try single(args, "abs") {
            case .integer(let n): return .integer(Swift.abs(n))
            case .double(let d): return .double(Swift.abs(d))
            default: throw LispError("abs: 数値が必要です")
            }
        }
        define("min") { args, _ in try numericExtremum(args, "min", keepLeft: { $0 <= $1 }) }
        define("max") { args, _ in try numericExtremum(args, "max", keepLeft: { $0 >= $1 }) }
        define("floor") { args, _ in .integer(Int(try asDouble(try single(args, "floor")).rounded(.down))) }
        define("ceiling") { args, _ in .integer(Int(try asDouble(try single(args, "ceiling")).rounded(.up))) }
        define("round") { args, _ in .integer(Int(try asDouble(try single(args, "round")).rounded())) }

        define("=") { args, _ in try numericCompare(args, "=") { $0 == $1 } }
        define("/=") { args, _ in
            guard args.count == 2 else { throw LispError("/=: 引数は2つ必要です") }
            return try asDouble(args[0]) != asDouble(args[1]) ? .t : .nilValue
        }
        define("<") { args, _ in try numericCompare(args, "<") { $0 < $1 } }
        define(">") { args, _ in try numericCompare(args, ">") { $0 > $1 } }
        define("<=") { args, _ in try numericCompare(args, "<=") { $0 <= $1 } }
        define(">=") { args, _ in try numericCompare(args, ">=") { $0 >= $1 } }

        // MARK: 述語

        define("null") { args, _ in try single(args, "null").isNil ? .t : .nilValue }
        define("not") { args, _ in try single(args, "not").isNil ? .t : .nilValue }
        define("consp") { args, _ in
            if case .cons = try single(args, "consp") { return .t }
            return .nilValue
        }
        define("listp") { args, _ in
            switch try single(args, "listp") {
            case .cons, .nilValue: return .t
            default: return .nilValue
            }
        }
        define("symbolp") { args, _ in
            switch try single(args, "symbolp") {
            case .symbol, .nilValue, .t: return .t
            default: return .nilValue
            }
        }
        define("stringp") { args, _ in
            if case .string = try single(args, "stringp") { return .t }
            return .nilValue
        }
        define("numberp") { args, _ in
            switch try single(args, "numberp") {
            case .integer, .double: return .t
            default: return .nilValue
            }
        }
        define("integerp") { args, _ in
            if case .integer = try single(args, "integerp") { return .t }
            return .nilValue
        }
        define("characterp") { args, _ in
            if case .character = try single(args, "characterp") { return .t }
            return .nilValue
        }
        define("functionp") { args, _ in
            switch try single(args, "functionp") {
            case .function, .builtin: return .t
            default: return .nilValue
            }
        }
        define("eq") { args, _ in try binaryEquality(args, "eq", LispEquality.eql) }
        define("eql") { args, _ in try binaryEquality(args, "eql", LispEquality.eql) }
        define("equal") { args, _ in try binaryEquality(args, "equal", LispEquality.equal) }

        // MARK: リスト

        define("car") { args, _ in
            switch try single(args, "car") {
            case .cons(let head, _): return head
            case .nilValue: return .nilValue
            default: throw LispError("car: リストが必要です")
            }
        }
        define("cdr") { args, _ in
            switch try single(args, "cdr") {
            case .cons(_, let tail): return tail
            case .nilValue: return .nilValue
            default: throw LispError("cdr: リストが必要です")
            }
        }
        define("cons") { args, _ in
            guard args.count == 2 else { throw LispError("cons: 引数は2つ必要です") }
            return .cons(args[0], args[1])
        }
        define("list") { args, _ in .list(args) }
        define("append") { args, _ in
            var items: [LispValue] = []
            for arg in args {
                guard let array = arg.toArray() else {
                    throw LispError("append: リストが必要です")
                }
                items.append(contentsOf: array)
            }
            return .list(items)
        }
        define("reverse") { args, _ in
            guard let items = try single(args, "reverse").toArray() else {
                throw LispError("reverse: リストが必要です")
            }
            return .list(items.reversed())
        }
        define("length") { args, _ in
            switch try single(args, "length") {
            case .string(let s): return .integer(s.count)
            case .vector(let v): return .integer(v.count)
            case .nilValue: return .integer(0)
            case .cons(_, _):
                guard let items = args[0].toArray() else {
                    throw LispError("length: 真リストが必要です")
                }
                return .integer(items.count)
            default: throw LispError("length: リスト・文字列・ベクタが必要です")
            }
        }
        define("mapcar") { args, interpreter in
            guard args.count >= 2 else { throw LispError("mapcar: 引数が足りません") }
            let lists = try args.dropFirst().map { arg -> [LispValue] in
                guard let items = arg.toArray() else {
                    throw LispError("mapcar: リストが必要です")
                }
                return items
            }
            let count = lists.map(\.count).min() ?? 0
            var results: [LispValue] = []
            for index in 0..<count {
                results.append(try interpreter.apply(args[0], lists.map { $0[index] }))
            }
            return .list(results)
        }
        define("mapc") { args, interpreter in
            guard args.count >= 2, let items = args[1].toArray() else {
                throw LispError("mapc: 引数が不正です")
            }
            for item in items {
                _ = try interpreter.apply(args[0], [item])
            }
            return args[1]
        }
        define("member") { args, _ in
            guard args.count == 2 else { throw LispError("member: 引数は2つ必要です") }
            var current = args[1]
            while case .cons(let head, let tail) = current {
                if LispEquality.eql(head, args[0]) { return current }
                current = tail
            }
            return .nilValue
        }
        define("assoc") { args, _ in
            guard args.count == 2, let pairs = args[1].toArray() else {
                throw LispError("assoc: 引数が不正です")
            }
            for pair in pairs {
                if case .cons(let key, _) = pair, LispEquality.eql(key, args[0]) {
                    return pair
                }
            }
            return .nilValue
        }
        define("nth") { args, _ in
            guard args.count == 2, case .integer(let n) = args[0],
                  let items = args[1].toArray() else {
                throw LispError("nth: (nth 番号 リスト) の形式で指定してください")
            }
            return (n >= 0 && n < items.count) ? items[n] : .nilValue
        }
        define("elt") { args, _ in
            guard args.count == 2, case .integer(let n) = args[1] else {
                throw LispError("elt: (elt 列 番号) の形式で指定してください")
            }
            switch args[0] {
            case .string(let s):
                guard n >= 0, n < s.count else { throw LispError("elt: 範囲外です") }
                return .character(Array(s)[n])
            case .vector(let v):
                guard n >= 0, n < v.count else { throw LispError("elt: 範囲外です") }
                return v[n]
            default:
                guard let items = args[0].toArray(), n >= 0, n < items.count else {
                    throw LispError("elt: 範囲外です")
                }
                return items[n]
            }
        }

        // MARK: 文字列

        define("string-append") { args, _ in
            var result = ""
            for arg in args {
                guard case .string(let s) = arg else {
                    throw LispError("string-append: 文字列が必要です")
                }
                result += s
            }
            return .string(result)
        }
        define("substring") { args, _ in
            guard args.count == 3,
                  case .string(let s) = args[0],
                  case .integer(let start) = args[1],
                  case .integer(let end) = args[2] else {
                throw LispError("substring: (substring 文字列 開始 終了) の形式で指定してください")
            }
            let chars = Array(s)
            guard start >= 0, end <= chars.count, start <= end else {
                throw LispError("substring: 範囲外です")
            }
            return .string(String(chars[start..<end]))
        }
        define("string=") { args, _ in
            let (a, b) = try twoStrings(args, "string=")
            return a == b ? .t : .nilValue
        }
        define("string<") { args, _ in
            let (a, b) = try twoStrings(args, "string<")
            return a < b ? .t : .nilValue
        }
        define("string-index") { args, _ in
            guard args.count >= 2 else { throw LispError("string-index: 引数が足りません") }
            let (pattern, target) = try twoStrings(Array(args.prefix(2)), "string-index")
            let chars = Array(target)
            let patternChars = Array(pattern)
            var start = 0
            if args.count >= 3, case .integer(let s) = args[2] { start = s }
            guard !patternChars.isEmpty, start >= 0 else { return .nilValue }
            var index = start
            while index + patternChars.count <= chars.count {
                if Array(chars[index..<(index + patternChars.count)]) == patternChars {
                    return .integer(index)
                }
                index += 1
            }
            return .nilValue
        }
        define("char-code") { args, _ in
            guard case .character(let c) = try single(args, "char-code"),
                  let scalar = c.unicodeScalars.first else {
                throw LispError("char-code: 文字が必要です")
            }
            return .integer(Int(scalar.value))
        }
        define("code-char") { args, _ in
            guard case .integer(let n) = try single(args, "code-char"),
                  let scalar = Unicode.Scalar(n) else {
                throw LispError("code-char: 不正なコードです")
            }
            return .character(Character(scalar))
        }
        define("parse-number") { args, _ in
            guard case .string(let s) = try single(args, "parse-number") else {
                throw LispError("parse-number: 文字列が必要です")
            }
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let n = Int(trimmed) { return .integer(n) }
            if let d = Double(trimmed) { return .double(d) }
            throw LispError("parse-number: 数値として解釈できません: \(s)")
        }
        define("format") { args, interpreter in
            guard args.count >= 2, case .string(let template) = args[1] else {
                throw LispError("format: (format 出力先 書式 引数...) の形式で指定してください")
            }
            let text = try formatString(template, Array(args.dropFirst(2)))
            if args[0].isNil {
                return .string(text)
            }
            interpreter.output(text)
            return .nilValue
        }

        // MARK: 関数適用ほか

        define("funcall") { args, interpreter in
            guard let fn = args.first else { throw LispError("funcall: 関数がありません") }
            return try interpreter.apply(fn, Array(args.dropFirst()))
        }
        define("apply") { args, interpreter in
            guard args.count >= 2, let last = args.last?.toArray() else {
                throw LispError("apply: 最後の引数はリストが必要です")
            }
            let fixed = Array(args.dropFirst().dropLast())
            return try interpreter.apply(args[0], fixed + last)
        }
        define("error") { args, _ in
            let message = args.map { $0.displayed() }.joined(separator: " ")
            throw LispError(message.isEmpty ? "エラー" : message)
        }
        define("gensym") { _, _ in
            gensymCounter += 1
            return .symbol("#:g\(gensymCounter)")
        }

        // MARK: ILOS(オブジェクトシステム)

        define("create") { args, _ in
            guard case .classObject(let cls) = args.first else {
                throw LispError("create: (create (class 名前) :slot 値 ...) の形式で指定してください")
            }
            // :initarg → 値 の対応表を作る
            var initargs: [String: LispValue] = [:]
            var index = 1
            while index + 1 < args.count + 1, index < args.count {
                guard case .symbol(let key) = args[index], index + 1 < args.count else {
                    throw LispError("create: 初期化引数が不正です")
                }
                initargs[key] = args[index + 1]
                index += 2
            }
            // スロットを初期化(initarg 優先、なければ initform、それもなければ未束縛)
            var slots: [String: LispValue] = [:]
            for slot in cls.allSlots {
                if let initarg = slot.initarg, let value = initargs[initarg] {
                    slots[slot.name] = value
                } else if let initform = slot.initform {
                    slots[slot.name] = try interpreter.eval(initform, in: interpreter.globals)
                }
            }
            return .instance(LispInstance(isa: cls, slots: slots))
        }
        define("instancep") { args, _ in
            if case .instance = try single(args, "instancep") { return .t }
            return .nilValue
        }
        define("class-of") { args, _ in
            if case .instance(let obj) = try single(args, "class-of") {
                return .classObject(obj.isa)
            }
            throw LispError("class-of: インスタンスが必要です")
        }
        define("subclassp") { args, _ in
            guard args.count == 2,
                  case .classObject(let a) = args[0],
                  case .classObject(let b) = args[1] else {
                throw LispError("subclassp: (subclassp クラス クラス) の形式で指定してください")
            }
            return a.isSubclass(of: b) ? .t : .nilValue
        }
        define("generic-function-p") { args, _ in
            if case .generic = try single(args, "generic-function-p") { return .t }
            return .nilValue
        }
        define("class-name") { args, _ in
            if case .classObject(let cls) = try single(args, "class-name") {
                return .symbol(cls.name)
            }
            throw LispError("class-name: クラスが必要です")
        }
        define("slot-value") { args, _ in
            guard args.count == 2,
                  case .instance(let obj) = args[0],
                  case .symbol(let name) = args[1] else {
                throw LispError("slot-value: (slot-value インスタンス 'スロット名) の形式で指定してください")
            }
            guard let value = obj.slots[name] else {
                throw LispError("slot-value: スロット \(name) は未束縛です")
            }
            return value
        }
        define("set-slot-value") { args, _ in
            guard args.count == 3,
                  case .instance(let obj) = args[0],
                  case .symbol(let name) = args[1] else {
                throw LispError("set-slot-value: (set-slot-value インスタンス 'スロット名 値) の形式で指定してください")
            }
            obj.slots[name] = args[2]
            return args[2]
        }

        // MARK: テキスト処理ユーティリティ(マクロでの実用性のための拡張。ISO外)

        define("string-split") { args, _ in
            let (target, separator) = try twoStrings(args, "string-split")
            guard !separator.isEmpty else {
                throw LispError("string-split: 区切り文字が空です")
            }
            return .list(target.components(separatedBy: separator).map { .string($0) })
        }
        define("string-join") { args, _ in
            guard args.count == 2,
                  let items = args[0].toArray(),
                  case .string(let separator) = args[1] else {
                throw LispError("string-join: (string-join リスト 区切り) の形式で指定してください")
            }
            let strings = try items.map { item -> String in
                guard case .string(let s) = item else {
                    throw LispError("string-join: 文字列のリストが必要です")
                }
                return s
            }
            return .string(strings.joined(separator: separator))
        }
        define("string-upcase") { args, _ in
            guard case .string(let s) = try single(args, "string-upcase") else {
                throw LispError("string-upcase: 文字列が必要です")
            }
            return .string(s.uppercased())
        }
        define("string-downcase") { args, _ in
            guard case .string(let s) = try single(args, "string-downcase") else {
                throw LispError("string-downcase: 文字列が必要です")
            }
            return .string(s.lowercased())
        }
        define("sort") { args, _ in
            guard let items = try single(args, "sort").toArray() else {
                throw LispError("sort: リストが必要です")
            }
            if items.allSatisfy({ if case .string = $0 { return true }; return false }) {
                let strings = items.compactMap { item -> String? in
                    if case .string(let s) = item { return s }
                    return nil
                }
                return .list(strings.sorted().map { .string($0) })
            }
            let numbers = try items.map { try asDouble($0) }
            let sorted = zip(numbers, items).sorted { $0.0 < $1.0 }.map(\.1)
            return .list(sorted)
        }

        // MARK: 正規表現(NSRegularExpression ベース。文字列単位で動く)
        //
        // ^ と $ が各行の行頭・行末にもマッチするよう anchorsMatchLines を付ける
        // (テキスト編集での実用性のため)。位置は他の文字列関数と同じ
        // Character(書記素)単位で数える。

        define("re-match-p") { args, _ in
            let (pattern, target) = try twoStrings(args, "re-match-p")
            let regex = try Self.compileRegex(pattern, "re-match-p")
            let range = NSRange(location: 0, length: (target as NSString).length)
            return regex.firstMatch(in: target, range: range) != nil ? .t : .nilValue
        }
        define("re-match") { args, _ in
            guard args.count >= 2 else { throw LispError("re-match: 引数が足りません") }
            let (pattern, target) = try twoStrings(Array(args.prefix(2)), "re-match")
            let regex = try Self.compileRegex(pattern, "re-match")
            let ns = target as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: target, range: range) else { return .nilValue }
            return .string(ns.substring(with: match.range))
        }
        define("re-search") { args, _ in
            guard args.count >= 2 else { throw LispError("re-search: 引数が足りません") }
            let (pattern, target) = try twoStrings(Array(args.prefix(2)), "re-search")
            let regex = try Self.compileRegex(pattern, "re-search")
            let chars = Array(target)
            var start = 0
            if args.count >= 3, case .integer(let s) = args[2] { start = s }
            guard start >= 0, start <= chars.count else { return .nilValue }
            let ns = target as NSString
            // Character 単位の開始位置を UTF-16 オフセットへ変換
            let startUTF16 = (String(chars.prefix(start)) as NSString).length
            let range = NSRange(location: startUTF16, length: ns.length - startUTF16)
            guard let match = regex.firstMatch(in: target, range: range) else { return .nilValue }
            // マッチ開始の UTF-16 オフセットを Character 単位へ戻す
            return .integer(ns.substring(to: match.range.location).count)
        }
        define("re-replace") { args, _ in
            guard args.count == 3,
                  case .string(let pattern) = args[0],
                  case .string(let template) = args[1],
                  case .string(let target) = args[2] else {
                throw LispError("re-replace: (re-replace 正規表現 置換 文字列) の形式で指定してください")
            }
            let regex = try Self.compileRegex(pattern, "re-replace")
            let ns = target as NSString
            let range = NSRange(location: 0, length: ns.length)
            let result = regex.stringByReplacingMatches(in: target, range: range, withTemplate: template)
            return .string(result)
        }
        define("re-split") { args, _ in
            let (pattern, target) = try twoStrings(args, "re-split")
            let regex = try Self.compileRegex(pattern, "re-split")
            let ns = target as NSString
            let full = NSRange(location: 0, length: ns.length)
            var pieces: [String] = []
            var last = 0
            regex.enumerateMatches(in: target, range: full) { match, _, _ in
                guard let match = match, match.range.length > 0 else { return }
                pieces.append(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
                last = match.range.location + match.range.length
            }
            pieces.append(ns.substring(from: last))
            return .list(pieces.map { .string($0) })
        }
        define("re-matches") { args, _ in
            // マッチした部分文字列をすべて返す。長さ 0 の空マッチは含めない。
            // (u? のような常に空にマッチしうるパターンでも「実際に文字を
            //  拾えた箇所」だけを返すので、grep 等で実用的に使える)
            let (pattern, target) = try twoStrings(args, "re-matches")
            let regex = try Self.compileRegex(pattern, "re-matches")
            let ns = target as NSString
            let full = NSRange(location: 0, length: ns.length)
            var results: [LispValue] = []
            regex.enumerateMatches(in: target, range: full) { match, _, _ in
                guard let match = match, match.range.length > 0 else { return }
                results.append(.string(ns.substring(with: match.range)))
            }
            return .list(results)
        }
    }

    /// 正規表現をコンパイルする。不正なら分かりやすいエラーを投げる
    static func compileRegex(_ pattern: String, _ name: String) throws -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            throw LispError("\(name): 正規表現が不正です: \(pattern)")
        }
        return regex
    }

    // MARK: - convert(特殊形式から呼ばれる)

    static func convert(_ value: LispValue, to className: String) throws -> LispValue {
        switch className {
        case "<string>":
            switch value {
            case .string: return value
            case .integer, .double: return .string(value.displayed())
            case .symbol(let s): return .string(s)
            case .character(let c): return .string(String(c))
            case .cons, .nilValue:
                guard let items = value.toArray() else { break }
                var result = ""
                for item in items {
                    guard case .character(let c) = item else {
                        throw LispError("convert: 文字のリストが必要です")
                    }
                    result.append(c)
                }
                return .string(result)
            default: break
            }
        case "<integer>":
            switch value {
            case .integer: return value
            case .double(let d): return .integer(Int(d))
            case .string(let s):
                guard let n = Int(s.trimmingCharacters(in: .whitespaces)) else {
                    throw LispError("convert: 整数として解釈できません: \(s)")
                }
                return .integer(n)
            case .character(let c):
                if let scalar = c.unicodeScalars.first { return .integer(Int(scalar.value)) }
            default: break
            }
        case "<float>":
            switch value {
            case .double: return value
            case .integer(let n): return .double(Double(n))
            case .string(let s):
                guard let d = Double(s.trimmingCharacters(in: .whitespaces)) else {
                    throw LispError("convert: 数値として解釈できません: \(s)")
                }
                return .double(d)
            default: break
            }
        case "<symbol>":
            if case .string(let s) = value { return .symbol(s.lowercased()) }
            if case .symbol = value { return value }
        case "<list>":
            switch value {
            case .cons, .nilValue: return value
            case .string(let s): return .list(s.map { .character($0) })
            case .vector(let v): return .list(v)
            default: break
            }
        default:
            throw LispError("convert: 未対応のクラスです: \(className)")
        }
        throw LispError("convert: \(value.printed()) を \(className) に変換できません")
    }

    private static var gensymCounter = 0

    // MARK: - format 書式

    private static func formatString(_ template: String, _ args: [LispValue]) throws -> String {
        var result = ""
        var argIndex = 0
        var chars = template.makeIterator()
        while let c = chars.next() {
            guard c == "~" else {
                result.append(c)
                continue
            }
            guard let directive = chars.next() else { break }
            switch directive {
            case "a", "A":
                guard argIndex < args.count else { throw LispError("format: 引数が足りません") }
                result += args[argIndex].displayed()
                argIndex += 1
            case "s", "S":
                guard argIndex < args.count else { throw LispError("format: 引数が足りません") }
                result += args[argIndex].printed()
                argIndex += 1
            case "d", "D":
                guard argIndex < args.count else { throw LispError("format: 引数が足りません") }
                guard case .integer(let n) = args[argIndex] else {
                    throw LispError("format: ~D には整数が必要です")
                }
                result += String(n)
                argIndex += 1
            case "%":
                result.append("\n")
            case "~":
                result.append("~")
            default:
                throw LispError("format: 未対応の書式指定です: ~\(directive)")
            }
        }
        return result
    }

    // MARK: - 数値ヘルパ

    private static func asDouble(_ value: LispValue) throws -> Double {
        switch value {
        case .integer(let n): return Double(n)
        case .double(let d): return d
        default: throw LispError("数値が必要です: \(value.printed())")
        }
    }

    private static func bothIntegers(_ a: LispValue, _ b: LispValue) -> (Int, Int)? {
        if case .integer(let x) = a, case .integer(let y) = b { return (x, y) }
        return nil
    }

    private static func numericAdd(_ a: LispValue, _ b: LispValue) throws -> LispValue {
        if let (x, y) = bothIntegers(a, b) { return .integer(x + y) }
        return .double(try asDouble(a) + asDouble(b))
    }

    private static func numericSub(_ a: LispValue, _ b: LispValue) throws -> LispValue {
        if let (x, y) = bothIntegers(a, b) { return .integer(x - y) }
        return .double(try asDouble(a) - asDouble(b))
    }

    private static func numericMul(_ a: LispValue, _ b: LispValue) throws -> LispValue {
        if let (x, y) = bothIntegers(a, b) { return .integer(x * y) }
        return .double(try asDouble(a) * asDouble(b))
    }

    private static func numericDiv(_ a: LispValue, _ b: LispValue) throws -> LispValue {
        if let (x, y) = bothIntegers(a, b) {
            guard y != 0 else { throw LispError("/: 0 で割ることはできません") }
            if x % y == 0 { return .integer(x / y) }
            return .double(Double(x) / Double(y))
        }
        let divisor = try asDouble(b)
        guard divisor != 0 else { throw LispError("/: 0 で割ることはできません") }
        return .double(try asDouble(a) / divisor)
    }

    private static func numericExtremum(
        _ args: [LispValue],
        _ name: String,
        keepLeft: (Double, Double) -> Bool
    ) throws -> LispValue {
        guard var best = args.first else { throw LispError("\(name): 引数がありません") }
        for arg in args.dropFirst() {
            if !keepLeft(try asDouble(best), try asDouble(arg)) {
                best = arg
            }
        }
        return best
    }

    private static func numericCompare(
        _ args: [LispValue],
        _ name: String,
        _ compare: (Double, Double) -> Bool
    ) throws -> LispValue {
        guard args.count >= 2 else { throw LispError("\(name): 引数は2つ以上必要です") }
        for index in 0..<(args.count - 1) {
            if !compare(try asDouble(args[index]), try asDouble(args[index + 1])) {
                return .nilValue
            }
        }
        return .t
    }

    // MARK: - 引数ヘルパ

    private static func single(_ args: [LispValue], _ name: String) throws -> LispValue {
        guard args.count == 1 else {
            throw LispError("\(name): 引数は1つ必要です")
        }
        return args[0]
    }

    private static func twoIntegers(_ args: [LispValue], _ name: String) throws -> (Int, Int) {
        guard args.count == 2,
              case .integer(let a) = args[0],
              case .integer(let b) = args[1] else {
            throw LispError("\(name): 整数2つが必要です")
        }
        return (a, b)
    }

    private static func twoStrings(_ args: [LispValue], _ name: String) throws -> (String, String) {
        guard args.count == 2,
              case .string(let a) = args[0],
              case .string(let b) = args[1] else {
            throw LispError("\(name): 文字列2つが必要です")
        }
        return (a, b)
    }

    private static func binaryEquality(
        _ args: [LispValue],
        _ name: String,
        _ compare: (LispValue, LispValue) -> Bool
    ) throws -> LispValue {
        guard args.count == 2 else {
            throw LispError("\(name): 引数は2つ必要です")
        }
        return compare(args[0], args[1]) ? .t : .nilValue
    }
}
