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

    /// ダイアログなどでユーザーの応答を待った時間を実行時間に数えないよう、
    /// 期限を延長する
    func extendDeadline(by interval: TimeInterval) {
        deadline = deadline?.addingTimeInterval(interval)
    }

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
        case .nilValue, .t, .integer, .double, .string, .character, .vector,
             .function, .builtin, .classObject, .instance, .generic:
            return form
        case .symbol(let name):
            // キーワードシンボル(:x など)は自己評価する
            if name.hasPrefix(":") {
                return form
            }
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
        case .generic(let generic):
            return try applyGeneric(generic, args)
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

        case "class":
            // (class 名前) → クラスオブジェクトを返す
            guard args.count == 1, case .symbol(let className) = args[0] else {
                throw LispError("class: (class 名前) の形式で指定してください")
            }
            guard case .classObject? = globals.lookup(className) else {
                throw LispError("class: 未定義のクラスです: \(className)")
            }
            return globals.lookup(className)

        case "defclass":
            return try evalDefclass(args, in: env)

        case "defgeneric":
            return try evalDefgeneric(args)

        case "defmethod":
            return try evalDefmethod(args, in: env)

        default:
            return nil // 特殊形式ではない → 関数適用へ
        }
    }

    // MARK: - ILOS(オブジェクトシステム)

    /// (defclass 名前 (親...) ((スロット :initform 式 :initarg :key :accessor 名 :reader 名)...))
    private func evalDefclass(_ args: [LispValue], in env: LispEnvironment) throws -> LispValue {
        guard args.count >= 2, case .symbol(let className) = args[0] else {
            throw LispError("defclass: (defclass 名前 (親...) (スロット...)) の形式で指定してください")
        }
        guard let superForms = args[1].toArray() else {
            throw LispError("defclass: 親クラスのリストが不正です")
        }
        let supers = try superForms.map { form -> LispClass in
            guard case .symbol(let superName) = form else {
                throw LispError("defclass: 親クラス名が不正です")
            }
            guard case .classObject(let cls)? = globals.lookup(superName) else {
                throw LispError("defclass: 未定義の親クラスです: \(superName)")
            }
            return cls
        }

        var slots: [LispSlotSpec] = []
        if args.count >= 3, let slotForms = args[2].toArray() {
            for slotForm in slotForms {
                slots.append(try parseSlotSpec(slotForm))
            }
        }

        let newClass = LispClass(name: className, directSuperclasses: supers, directSlots: slots)
        try newClass.finalize()
        globals.define(className, .classObject(newClass))

        // アクセサ(:accessor / :reader)を総称関数として定義する
        for slot in newClass.allSlots {
            if let accessor = slot.accessor {
                defineSlotReader(accessor, slot: slot.name, on: newClass)
                defineSlotWriter("set-" + accessor, slot: slot.name, on: newClass)
            }
            if let reader = slot.reader {
                defineSlotReader(reader, slot: slot.name, on: newClass)
            }
        }
        return .symbol(className)
    }

    private func parseSlotSpec(_ form: LispValue) throws -> LispSlotSpec {
        // スロットは (名前 :option 値 ...) または 名前 のどちらか
        if case .symbol(let name) = form {
            return LispSlotSpec(name: name, initform: nil, initarg: nil, accessor: nil, reader: nil)
        }
        guard let parts = form.toArray(), let first = parts.first,
              case .symbol(let name) = first else {
            throw LispError("defclass: スロット定義が不正です")
        }
        var initform: LispValue?
        var initarg: String?
        var accessor: String?
        var reader: String?
        var index = 1
        while index + 1 < parts.count + 1, index < parts.count {
            guard case .symbol(let option) = parts[index], index + 1 < parts.count else {
                throw LispError("defclass: スロットオプションが不正です: \(name)")
            }
            let value = parts[index + 1]
            switch option {
            case ":initform": initform = value
            case ":initarg":
                if case .symbol(let key) = value { initarg = key }
                else { throw LispError("defclass: :initarg にはキーワードが必要です") }
            case ":accessor":
                if case .symbol(let fn) = value { accessor = fn }
                else { throw LispError("defclass: :accessor には名前が必要です") }
            case ":reader":
                if case .symbol(let fn) = value { reader = fn }
                else { throw LispError("defclass: :reader には名前が必要です") }
            default:
                throw LispError("defclass: 未対応のスロットオプションです: \(option)")
            }
            index += 2
        }
        return LispSlotSpec(name: name, initform: initform, initarg: initarg, accessor: accessor, reader: reader)
    }

    private func defineSlotReader(_ name: String, slot: String, on cls: LispClass) {
        let generic = ensureGeneric(name)
        let reader = LispBuiltin(name) { args, _ in
            guard case .instance(let obj) = args.first else {
                throw LispError("\(name): インスタンスが必要です")
            }
            guard let value = obj.slots[slot] else {
                throw LispError("\(name): スロット \(slot) は未束縛です")
            }
            return value
        }
        generic.addMethod(LispMethod(
            qualifier: .primary, specializer: cls,
            function: LispFunction(name: name, parameters: ["self"], restParameter: nil,
                                   body: [], closure: globals, builtinBody: reader)
        ))
    }

    private func defineSlotWriter(_ name: String, slot: String, on cls: LispClass) {
        let generic = ensureGeneric(name)
        let writer = LispBuiltin(name) { args, _ in
            guard args.count == 2, case .instance(let obj) = args[0] else {
                throw LispError("\(name): (\(name) インスタンス 値) の形式で指定してください")
            }
            obj.slots[slot] = args[1]
            return args[1]
        }
        generic.addMethod(LispMethod(
            qualifier: .primary, specializer: cls,
            function: LispFunction(name: name, parameters: ["self", "value"], restParameter: nil,
                                   body: [], closure: globals, builtinBody: writer)
        ))
    }

    private func ensureGeneric(_ name: String) -> LispGeneric {
        if case .generic(let existing)? = globals.lookup(name) {
            return existing
        }
        let generic = LispGeneric(name: name)
        globals.define(name, .generic(generic))
        return generic
    }

    /// (defgeneric 名前 (引数...))
    private func evalDefgeneric(_ args: [LispValue]) throws -> LispValue {
        guard case .symbol(let name)? = args.first else {
            throw LispError("defgeneric: 名前が必要です")
        }
        _ = ensureGeneric(name)
        return .symbol(name)
    }

    /// (defmethod 名前 [修飾子] ((引数 クラス) 引数...) 本体...)
    private func evalDefmethod(_ args: [LispValue], in env: LispEnvironment) throws -> LispValue {
        guard case .symbol(let name)? = args.first else {
            throw LispError("defmethod: 名前が必要です")
        }
        var index = 1
        var qualifier: LispMethod.Qualifier = .primary
        if index < args.count, case .symbol(let q) = args[index] {
            switch q {
            case ":before": qualifier = .before; index += 1
            case ":after": qualifier = .after; index += 1
            case ":around": qualifier = .around; index += 1
            default: break
            }
        }
        guard index < args.count, let paramForms = args[index].toArray(), !paramForms.isEmpty else {
            throw LispError("defmethod: 引数リストが不正です")
        }
        index += 1

        // 第 1 引数の (変数 クラス) からスペシャライザを取り出す
        var params: [String] = []
        var specializer: LispClass?
        for (position, paramForm) in paramForms.enumerated() {
            if case .symbol(let paramName) = paramForm {
                params.append(paramName)
            } else if let pair = paramForm.toArray(), pair.count == 2,
                      case .symbol(let paramName) = pair[0],
                      case .symbol(let clsName) = pair[1] {
                params.append(paramName)
                if position == 0 {
                    guard case .classObject(let cls)? = globals.lookup(clsName) else {
                        throw LispError("defmethod: 未定義のクラスです: \(clsName)")
                    }
                    specializer = cls
                }
            } else {
                throw LispError("defmethod: 引数指定が不正です")
            }
        }
        guard let cls = specializer else {
            throw LispError("defmethod: 第1引数に (変数 クラス) の指定が必要です")
        }

        let generic = ensureGeneric(name)
        let function = LispFunction(
            name: name, parameters: params, restParameter: nil,
            body: Array(args.dropFirst(index)), closure: env
        )
        generic.addMethod(LispMethod(qualifier: qualifier, specializer: cls, function: function))
        return .symbol(name)
    }

    /// 総称関数の呼び出し。第 1 引数のクラスで適用メソッドを選び、
    /// :around → :before → primary(+ call-next-method)→ :after の順で結合する。
    func applyGeneric(_ generic: LispGeneric, _ args: [LispValue]) throws -> LispValue {
        guard let receiver = args.first else {
            throw LispError("\(generic.name): 引数が必要です")
        }
        let receiverClass = try classOf(receiver)

        // 適用可能メソッドを優先順位(継承の近い順)で並べる
        func applicable(_ qualifier: LispMethod.Qualifier) -> [LispMethod] {
            let matched = generic.methods.filter {
                $0.qualifier == qualifier && receiverClass.isSubclass(of: $0.specializer)
            }
            return matched.sorted { a, b in
                precedenceIndex(receiverClass, a.specializer) < precedenceIndex(receiverClass, b.specializer)
            }
        }

        let arounds = applicable(.around)
        let befores = applicable(.before)
        let afters = applicable(.after).reversed().map { $0 } // 最も特定的なものを後に
        let primaries = applicable(.primary)

        // primary チェーン(call-next-method で次を呼ぶ)
        func invokePrimaryChain(_ remaining: [LispMethod]) throws -> LispValue {
            guard let method = remaining.first else {
                throw LispError("\(generic.name): 適用できるメソッドがありません")
            }
            return try invoke(method.function, args, nextMethods: Array(remaining.dropFirst()),
                              generic: generic, allArgs: args)
        }

        // effective method: around がなければ before → primary → after
        func core() throws -> LispValue {
            for method in befores {
                _ = try invoke(method.function, args, nextMethods: [], generic: generic, allArgs: args)
            }
            let result = try invokePrimaryChain(primaries)
            for method in afters {
                _ = try invoke(method.function, args, nextMethods: [], generic: generic, allArgs: args)
            }
            return result
        }

        if arounds.isEmpty {
            return try core()
        }
        // around チェーン: call-next-method で次の around、最後に core を呼ぶ
        func invokeAroundChain(_ remaining: [LispMethod]) throws -> LispValue {
            guard let method = remaining.first else {
                return try core()
            }
            return try invoke(
                method.function, args, nextMethods: [], generic: generic, allArgs: args,
                nextThunk: { try invokeAroundChain(Array(remaining.dropFirst())) }
            )
        }
        return try invokeAroundChain(arounds)
    }

    /// メソッド本体を呼ぶ。call-next-method / next-method-p を環境に束縛する。
    private func invoke(
        _ function: LispFunction,
        _ args: [LispValue],
        nextMethods: [LispMethod],
        generic: LispGeneric,
        allArgs: [LispValue],
        nextThunk: (() throws -> LispValue)? = nil
    ) throws -> LispValue {
        // builtin(アクセサ)ならそのまま
        if let builtin = function.builtinBody {
            return try builtin.body(args, self)
        }

        let env = LispEnvironment(parent: function.closure)
        for (name, value) in zip(function.parameters, args) {
            env.define(name, value)
        }

        let hasNext = !nextMethods.isEmpty || nextThunk != nil
        env.define("call-next-method", .builtin(LispBuiltin("call-next-method") { [weak self] callArgs, _ in
            guard let self else { return .nilValue }
            let forwardArgs = callArgs.isEmpty ? args : callArgs
            if let nextThunk { return try nextThunk() }
            guard let next = nextMethods.first else {
                throw LispError("call-next-method: 次のメソッドがありません")
            }
            return try self.invoke(next.function, forwardArgs,
                                   nextMethods: Array(nextMethods.dropFirst()),
                                   generic: generic, allArgs: allArgs)
        }))
        env.define("next-method-p", .builtin(LispBuiltin("next-method-p") { _, _ in
            hasNext ? .t : .nilValue
        }))

        var result = LispValue.nilValue
        for form in function.body {
            result = try eval(form, in: env)
        }
        return result
    }

    private func precedenceIndex(_ cls: LispClass, _ target: LispClass) -> Int {
        cls.precedenceList.firstIndex { $0 === target } ?? Int.max
    }

    /// 値のクラス(組み込み型は擬似クラスを返す)
    func classOf(_ value: LispValue) throws -> LispClass {
        switch value {
        case .instance(let obj):
            return obj.isa
        default:
            throw LispError("総称関数の第1引数はインスタンスである必要があります: \(value.printed())")
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
