import Foundation

/// マクロからのダイアログ要求(表示は MacroEngine / テストが担う)
enum MacroDialogRequest {
    case alert(message: String)
    case confirm(message: String)
    case prompt(message: String, defaultText: String)
}

/// ファイル操作(要件 §5.4)とダイアログ(§5.5)の組み込み関数。
/// ファイルアクセスはアプリの Documents フォルダ(「この iPad 内/ichiseEdit」)
/// 配下に限定し、相対パスのみ受け付ける。
enum LispSystemAPI {

    static func install(
        into interpreter: LispInterpreter,
        filesDirectory: URL,
        presentDialog: @escaping (MacroDialogRequest, @escaping (LispValue) -> Void) -> Void
    ) {
        let globals = interpreter.globals

        func define(_ name: String, _ body: @escaping ([LispValue], LispInterpreter) throws -> LispValue) {
            globals.define(name, .builtin(LispBuiltin(name, body)))
        }

        // MARK: ファイル操作(サンドボックス内)

        define("file-read") { args, _ in
            let url = try resolve(try pathArgument(args, "file-read"), base: filesDirectory)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw LispError("file-read: 読み込めません: \(args[0].displayed())")
            }
            return .string(text)
        }
        define("file-write") { args, _ in
            guard args.count == 2,
                  case .string(let path) = args[0],
                  case .string(let content) = args[1] else {
                throw LispError("file-write: (file-write パス 文字列) の形式で指定してください")
            }
            let url = try resolve(path, base: filesDirectory)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw LispError("file-write: 書き込めません: \(path)")
            }
            return .nilValue
        }
        define("file-list") { args, _ in
            let path: String
            if args.isEmpty {
                path = ""
            } else {
                path = try pathArgument(args, "file-list")
            }
            let url = try resolve(path, base: filesDirectory)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                throw LispError("file-list: フォルダを読めません: \(path)")
            }
            return .list(names.sorted().map { .string($0) })
        }
        define("file-exists-p") { args, _ in
            let url = try resolve(try pathArgument(args, "file-exists-p"), base: filesDirectory)
            return FileManager.default.fileExists(atPath: url.path) ? .t : .nilValue
        }

        // MARK: ダイアログ

        func awaitDialog(_ request: MacroDialogRequest, _ interpreter: LispInterpreter) throws -> LispValue {
            guard !Thread.isMainThread else {
                throw LispError("ダイアログはコマンド実行中にのみ使えます(マクロ読み込み中は不可)")
            }
            let semaphore = DispatchSemaphore(value: 0)
            var response = LispValue.nilValue
            let started = Date()
            DispatchQueue.main.async {
                presentDialog(request) { value in
                    response = value
                    semaphore.signal()
                }
            }
            semaphore.wait()
            // ユーザーが考えていた時間は実行タイムアウトに数えない
            interpreter.extendDeadline(by: Date().timeIntervalSince(started))
            return response
        }

        define("alert") { args, interpreter in
            guard args.count == 1, case .string(let message) = args[0] else {
                throw LispError("alert: 文字列が必要です")
            }
            _ = try awaitDialog(.alert(message: message), interpreter)
            return .nilValue
        }
        define("confirm") { args, interpreter in
            guard args.count == 1, case .string(let message) = args[0] else {
                throw LispError("confirm: 文字列が必要です")
            }
            return try awaitDialog(.confirm(message: message), interpreter)
        }
        define("prompt") { args, interpreter in
            guard let first = args.first, case .string(let message) = first else {
                throw LispError("prompt: 文字列が必要です")
            }
            var defaultText = ""
            if args.count >= 2, case .string(let text) = args[1] {
                defaultText = text
            }
            return try awaitDialog(.prompt(message: message, defaultText: defaultText), interpreter)
        }
    }

    // MARK: - パス解決(サンドボックス)

    /// 相対パスを基点フォルダ内に解決する。絶対パスや .. による脱出は拒否する
    static func resolve(_ path: String, base: URL) throws -> URL {
        guard !path.hasPrefix("/") else {
            throw LispError("絶対パスは使えません: \(path)")
        }
        let basePath = base.standardizedFileURL.path
        let url = base.appendingPathComponent(path).standardizedFileURL
        guard url.path == basePath || url.path.hasPrefix(basePath + "/") else {
            throw LispError("フォルダの外にはアクセスできません: \(path)")
        }
        return url
    }

    private static func pathArgument(_ args: [LispValue], _ name: String) throws -> String {
        guard args.count == 1, case .string(let path) = args[0] else {
            throw LispError("\(name): パス(文字列)が必要です")
        }
        return path
    }
}
