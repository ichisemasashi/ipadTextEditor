import Foundation

/// ISLISP サブセットのインタプリタ(評価器)。
/// 安全性: タイムアウトと評価深度の制限を持ち、暴走マクロからアプリを守る。
final class LispInterpreter {
    let globals = LispEnvironment()

    /// (format t ...) などの出力先(REPL コンソールが差し替える)
    var output: (String) -> Void = { _ in }
    /// 1 回の実行(run)に許す時間
    var timeoutSeconds: TimeInterval = 5
    /// 評価のネスト上限(Swift スタック保護。実行スレッドのスタックに合わせて調整)
    var maxDepth = 800

    private var deadline: Date?
    private var depth = 0
    private var evalCounter: UInt = 0
    private var constants: Set<String> = []
    private var dynamicVariables: [String: LispValue] = [:]

    init() {
        LispBuiltins.install(into: self)
    }

    // MARK: - エントリポイント

    /// ソース文字列を読み、全フォームを順に評価して最後の値を返す
    @discardableResult
    func run(_ source: String) throws -> LispValue {
        let forms = try LispReader.readAll(source)
        deadline = Date().addingTimeInterval(timeoutSeconds)
        defer { deadline = nil }
        var result = LispValue.nilValue
        for form in forms {
            result = try eval(form, in: globals)
        }
        return result
    }

    // MARK: - 評価器

    func eval(_ form: LispValue, in env: LispEnvironment) throws -> LispValue {
        try checkLimits()
        depth += 1
        defer { depth -= 1 }

        switch form {
        case .nilValue, .t, .integer, .double, .string, .character, .vector, .function, .builtin:
            return form
        case .symbol(let name):
            guard let value = env.lookup(name) else {
                throw LispError("未定義の変数です: \(name)")
            }
            return value
        case .cons(let head, let tail):
            guard let args = tail.toArray() else {
                throw LispError("不正な関数呼び出しです: \(form.printed())")
            }
            if case .symbol(let name) = head {
                if let result = try evalSpecialForm(name, args, in: env) {
                    return result
                }
                // マクロ展開
                if let value = env.lookup(name),
                   case .function(let fn) = value, fn.isMacro {
                    let expanded = try apply(.function(fn), args)
                    return try eval(expanded, in: env)
                }
            }
            let fn = try eval(head, in: env)
            let evaluated = try args.map { try eval($0, in: env) }
            return try apply(fn, evaluated)
        }
    }

    /// 関数適用(builtin からも使う)
    func apply(_ callee: LispValue, _ args: [LispValue]) throws -> LispValue {
        try checkLimits()
        depth += 1
        defer { depth -= 1 }

        switch callee {
        case .builtin(let builtin):
            return try builtin.body(args, self)
        case .function(let fn):
            let env = LispEnvironment(parent: fn.closure)
            if let rest = fn.restParameter {
                guard args.count >= fn.parameters.count else {
                    throw LispError("\(fn.name ?? "lambda"): 引数が足りません")
                }
                for (name, value) in zip(fn.parameters, args) {
                    env.define(name, value)
                }
                env.define(rest, .list(Array(args.dropFirst(fn.parameters.count))))
            } else {
                guard args.count == fn.parameters.count else {
                    throw LispError(
                        "\(fn.name ?? "lambda"): 引数の数が違います(期待 \(fn.parameters.count)、実際 \(args.count))"
                    )
                }
                for (name, value) in zip(fn.parameters, args) {
                    env.define(name, value)
                }
            }
            var result = LispValue.nilValue
            for form in fn.body {
                result = try eval(form, in: env)
            }
            return result
        default:
            throw LispError("関数ではありません: \(callee.printed())")
        }
    }

    // MARK: - 特殊形式

    private func evalSpecialForm(
        _ name: String,
        _ args: [LispValue],
        in env: LispEnvironment
    ) throws -> LispValue? {
        switch name {
        case "quote":
            try requireArity(args, 1, name)
            return args[0]

        case "quasiquote":
            try requireArity(args, 1, name)
            return try evalQuasiquote(args[0], depth: 1, in: env)

        case "if":
            guard args.count == 2 || args.count == 3 else {
                throw LispError("if: 引数の数が違います")
            }
            if try eval(args[0], in: env).isTruthy {
                return try eval(args[1], in: env)
            }
            return args.count == 3 ? try eval(args[2], in: env) : .nilValue

        case "cond":
            for clause in args {
                guard let parts = clause.toArray(), !parts.isEmpty else {
                    throw LispError("cond: 節が不正です")
                }
                let test = try eval(parts[0], in: env)
                if test.isTruthy {
                    var result = test
                    for form in parts.dropFirst() {
                        result = try eval(form, in: env)
                    }
                    return result
                }
            }
            return .nilValue

        case "case":
            guard let keyForm = args.first else {
                throw LispError("case: キーがありません")
            }
            let key = try eval(keyForm, in: env)
            for clause in args.dropFirst() {
                guard let parts = clause.toArray(), !parts.isEmpty else {
                    throw LispError("case: 節が不正です")
                }
                let matched: Bool
                if case .t = parts[0] {
                    matched = true
                } else if let keys = parts[0].toArray() {
                    matched = keys.contains { LispEquality.eql($0, key) }
                } else {
                    matched = false
                }
                if matched {
                    var result = LispValue.nilValue
                    for form in parts.dropFirst() {
                        result = try eval(form, in: env)
                    }
                    return result
                }
            }
            return .nilValue

        case "and":
            var result = LispValue.t
            for form in args {
                result = try eval(form, in: env)
                if result.isNil { return .nilValue }
            }
            return result

        case "or":
            for form in args {
                let result = try eval(form, in: env)
                if result.isTruthy { return result }
            }
            return .nilValue

        case "progn":
            var result = LispValue.nilValue
            for form in args {
                result = try eval(form, in: env)
            }
            return result

        case "let", "let*":
            guard let bindings = args.first?.toArray() else {
                throw LispError("\(name): 束縛リストが不正です")
            }
            let newEnv = LispEnvironment(parent: env)
            for binding in bindings {
                guard let pair = binding.toArray(), pair.count == 2,
                      case .symbol(let varName) = pair[0] else {
                    throw LispError("\(name): 束縛が不正です: \(binding.printed())")
                }
                let value = try eval(pair[1], in: name == "let*" ? newEnv : env)
                newEnv.define(varName, value)
            }
            var result = LispValue.nilValue
            for form in args.dropFirst() {
                result = try eval(form, in: newEnv)
            }
            return result

        case "lambda":
            guard let paramList = args.first else {
                throw LispError("lambda: 引数リストがありません")
            }
            let (params, rest) = try parseParameters(paramList)
            return .function(LispFunction(
                name: nil, parameters: params, restParameter: rest,
                body: Array(args.dropFirst()), closure: env
            ))

        case "defun", "defmacro":
            guard args.count >= 2,
                  case .symbol(let fnName) = args[0] else {
                throw LispError("\(name): 定義が不正です")
            }
            let (params, rest) = try parseParameters(args[1])
            let fn = LispFunction(
                name: fnName, parameters: params, restParameter: rest,
                body: Array(args.dropFirst(2)), closure: globals,
                isMacro: name == "defmacro"
            )
            globals.define(fnName, .function(fn))
            return .symbol(fnName)

        case "defglobal", "defconstant":
            guard args.count == 2, case .symbol(let varName) = args[0] else {
                throw LispError("\(name): 定義が不正です")
            }
            if constants.contains(varName) {
                throw LispError("定数は再定義できません: \(varName)")
            }
            globals.define(varName, try eval(args[1], in: env))
            if name == "defconstant" {
                constants.insert(varName)
            }
            return .symbol(varName)

        case "setq":
            guard args.count == 2, case .symbol(let varName) = args[0] else {
                throw LispError("setq: (setq 変数 値) の形式で指定してください")
            }
            if constants.contains(varName) {
                throw LispError("定数には代入できません: \(varName)")
            }
            let value = try eval(args[1], in: env)
            try env.set(varName, value)
            return value

        case "while":
            guard let test = args.first else {
                throw LispError("while: 条件がありません")
            }
            while try eval(test, in: env).isTruthy {
                for form in args.dropFirst() {
                    _ = try eval(form, in: env)
                }
            }
            return .nilValue

        case "for":
            return try evalFor(args, in: env)

        case "block":
            guard case .symbol(let blockName)? = args.first else {
                throw LispError("block: 名前がありません")
            }
            do {
                var result = LispValue.nilValue
                for form in args.dropFirst() {
                    result = try eval(form, in: env)
                }
                return result
            } catch let ret as LispBlockReturn where ret.name == blockName {
                return ret.value
            }

        case "return-from":
            guard args.count == 2, case .symbol(let blockName) = args[0] else {
                throw LispError("return-from: (return-from 名前 値) の形式で指定してください")
            }
            throw LispBlockReturn(name: blockName, value: try eval(args[1], in: env))

        case "catch":
            guard let tagForm = args.first else {
                throw LispError("catch: タグがありません")
            }
            let tag = try eval(tagForm, in: env)
            do {
                var result = LispValue.nilValue
                for form in args.dropFirst() {
                    result = try eval(form, in: env)
                }
                return result
            } catch let signal as LispThrowSignal where LispEquality.eql(signal.tag, tag) {
                return signal.value
            }

        case "throw":
            try requireArity(args, 2, name)
            let tag = try eval(args[0], in: env)
            let value = try eval(args[1], in: env)
            throw LispThrowSignal(tag: tag, value: value)

        case "unwind-protect":
            guard let protected = args.first else {
                throw LispError("unwind-protect: 本体がありません")
            }
            do {
                let result = try eval(protected, in: env)
                for cleanup in args.dropFirst() {
                    _ = try eval(cleanup, in: env)
                }
                return result
            } catch {
                for cleanup in args.dropFirst() {
                    _ = try? eval(cleanup, in: env)
                }
                throw error
            }

        case "function":
            try requireArity(args, 1, name)
            if case .symbol(let fnName) = args[0] {
                guard let value = env.lookup(fnName) else {
                    throw LispError("未定義の関数です: \(fnName)")
                }
                return value
            }
            return try eval(args[0], in: env)

        case "with-handler":
            guard let handlerForm = args.first else {
                throw LispError("with-handler: ハンドラがありません")
            }
            let handler = try eval(handlerForm, in: env)
            do {
                var result = LispValue.nilValue
                for form in args.dropFirst() {
                    result = try eval(form, in: env)
                }
                return result
            } catch let error as LispError {
                return try apply(handler, [.string(error.message)])
            }

        case "convert":
            guard args.count == 2, case .symbol(let className) = args[1] else {
                throw LispError("convert: (convert 値 <クラス>) の形式で指定してください")
            }
            return try LispBuiltins.convert(try eval(args[0], in: env), to: className)

        case "defdynamic":
            guard args.count == 2, case .symbol(let varName) = args[0] else {
                throw LispError("defdynamic: 定義が不正です")
            }
            dynamicVariables[varName] = try eval(args[1], in: env)
            return .symbol(varName)

        case "dynamic":
            guard args.count == 1, case .symbol(let varName) = args[0] else {
                throw LispError("dynamic: (dynamic 変数) の形式で指定してください")
            }
            guard let value = dynamicVariables[varName] else {
                throw LispError("未定義のダイナミック変数です: \(varName)")
            }
            return value

        case "dynamic-let":
            guard let bindings = args.first?.toArray() else {
                throw LispError("dynamic-let: 束縛リストが不正です")
            }
            var saved: [(String, LispValue?)] = []
            for binding in bindings {
                guard let pair = binding.toArray(), pair.count == 2,
                      case .symbol(let varName) = pair[0] else {
                    throw LispError("dynamic-let: 束縛が不正です")
                }
                saved.append((varName, dynamicVariables[varName]))
                dynamicVariables[varName] = try eval(pair[1], in: env)
            }
            defer {
                for (varName, old) in saved.reversed() {
                    dynamicVariables[varName] = old
                }
            }
            var result = LispValue.nilValue
            for form in args.dropFirst() {
                result = try eval(form, in: env)
            }
            return result

        default:
            return nil // 特殊形式ではない → 関数適用へ
        }
    }

    // MARK: - for 特殊形式

    /// (for ((var init [step])...) (test result...) body...)
    private func evalFor(_ args: [LispValue], in env: LispEnvironment) throws -> LispValue {
        guard args.count >= 2,
              let bindings = args[0].toArray(),
              let testClause = args[1].toArray(), !testClause.isEmpty else {
            throw LispError("for: (for (束縛...) (終了条件 結果...) 本体...) の形式で指定してください")
        }

        let loopEnv = LispEnvironment(parent: env)
        var steps: [(name: String, form: LispValue?)] = []
        for binding in bindings {
            guard let parts = binding.toArray(), parts.count >= 2,
                  case .symbol(let varName) = parts[0] else {
                throw LispError("for: 束縛が不正です")
            }
            loopEnv.define(varName, try eval(parts[1], in: env))
            steps.append((varName, parts.count >= 3 ? parts[2] : nil))
        }

        while true {
            if try eval(testClause[0], in: loopEnv).isTruthy {
                var result = LispValue.nilValue
                for form in testClause.dropFirst() {
                    result = try eval(form, in: loopEnv)
                }
                return result
            }
            for form in args.dropFirst(2) {
                _ = try eval(form, in: loopEnv)
            }
            // 更新式は同時評価してから代入する
            var newValues: [(String, LispValue)] = []
            for step in steps {
                if let stepForm = step.form {
                    newValues.append((step.name, try eval(stepForm, in: loopEnv)))
                }
            }
            for (varName, value) in newValues {
                loopEnv.define(varName, value)
            }
        }
    }

    // MARK: - quasiquote

    private func evalQuasiquote(
        _ form: LispValue,
        depth qqDepth: Int,
        in env: LispEnvironment
    ) throws -> LispValue {
        switch form {
        case .cons(.symbol("unquote"), let tail):
            guard let args = tail.toArray(), args.count == 1 else {
                throw LispError("unquote が不正です")
            }
            if qqDepth == 1 {
                return try eval(args[0], in: env)
            }
            return .list([
                .symbol("unquote"),
                try evalQuasiquote(args[0], depth: qqDepth - 1, in: env),
            ])
        case .cons(.symbol("quasiquote"), let tail):
            guard let args = tail.toArray(), args.count == 1 else {
                throw LispError("quasiquote が不正です")
            }
            return .list([
                .symbol("quasiquote"),
                try evalQuasiquote(args[0], depth: qqDepth + 1, in: env),
            ])
        case .cons:
            // リストを走査し、unquote-splicing を展開する
            var results: [LispValue] = []
            var current = form
            while case .cons(let head, let tail) = current {
                if case .cons(.symbol("unquote-splicing"), let spliceTail) = head, qqDepth == 1 {
                    guard let spliceArgs = spliceTail.toArray(), spliceArgs.count == 1 else {
                        throw LispError("unquote-splicing が不正です")
                    }
                    let value = try eval(spliceArgs[0], in: env)
                    guard let items = value.toArray() else {
                        throw LispError("unquote-splicing の結果がリストではありません")
                    }
                    results.append(contentsOf: items)
                } else {
                    results.append(try evalQuasiquote(head, depth: qqDepth, in: env))
                }
                current = tail
            }
            return .list(results)
        default:
            return form
        }
    }

    // MARK: - 補助

    private func parseParameters(_ list: LispValue) throws -> ([String], String?) {
        guard let items = list.toArray() else {
            throw LispError("引数リストが不正です: \(list.printed())")
        }
        var params: [String] = []
        var rest: String?
        var index = 0
        while index < items.count {
            guard case .symbol(let name) = items[index] else {
                throw LispError("引数名が不正です: \(items[index].printed())")
            }
            if name == "&rest" || name == ":rest" {
                guard index + 1 < items.count,
                      case .symbol(let restName) = items[index + 1] else {
                    throw LispError("&rest の後に引数名が必要です")
                }
                rest = restName
                index += 2
            } else {
                params.append(name)
                index += 1
            }
        }
        return (params, rest)
    }

    private func requireArity(_ args: [LispValue], _ count: Int, _ name: String) throws {
        guard args.count == count else {
            throw LispError("\(name): 引数の数が違います(期待 \(count)、実際 \(args.count))")
        }
    }

    private func checkLimits() throws {
        if depth > maxDepth {
            throw LispError("再帰が深すぎます(上限 \(maxDepth))")
        }
        evalCounter &+= 1
        if evalCounter % 256 == 0, let deadline, Date() > deadline {
            throw LispError("実行がタイムアウトしました(\(Int(timeoutSeconds))秒)")
        }
    }
}
