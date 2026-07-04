import UIKit
import AVFoundation

/// マクロからの iPadOS 連携要求(要件 §5.6)。UI 提示は MacroEngine が担う。
enum MacroPlatformRequest {
    /// 共有シート
    case share(text: String)
    /// AirPrint
    case print(text: String)
    /// 内蔵辞書パネル
    case dictionary(word: String)
    /// URL を既定アプリで開く
    case openURL(url: URL)
    /// ドキュメントピッカーで読み込み(結果テキスト or nil を返す)
    case pickFile(completion: (LispValue) -> Void)
    /// 保存先をユーザーが選んで書き出し
    case exportText(filename: String, text: String)
}

/// iPadOS 連携の組み込み関数(要件 §5.6)。
/// 権限ダイアログを伴わない OS 機能のみを提供する。
enum LispPlatformAPI {

    /// 読み上げは 1 つのシンセサイザを共有する(stop-speaking のため)
    static let speechSynthesizer = AVSpeechSynthesizer()

    static func install(
        into interpreter: LispInterpreter,
        present: @escaping (MacroPlatformRequest) -> Void
    ) {
        let globals = interpreter.globals

        func define(_ name: String, _ body: @escaping ([LispValue], LispInterpreter) throws -> LispValue) {
            globals.define(name, .builtin(LispBuiltin(name) { args, itp in
                try LispEditorAPI.runOnMain { try body(args, itp) }
            }))
        }

        // MARK: 文章支援

        define("speak") { args, _ in
            guard let first = args.first, case .string(let text) = first else {
                throw LispError("speak: 文字列が必要です")
            }
            let utterance = AVSpeechUtterance(string: text)
            if args.count >= 2, case .string(let lang) = args[1] {
                utterance.voice = AVSpeechSynthesisVoice(language: lang)
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            }
            if args.count >= 3, case .double(let rate) = args[2] {
                utterance.rate = Float(rate)
            } else if args.count >= 3, case .integer(let rate) = args[2] {
                utterance.rate = Float(rate)
            }
            speechSynthesizer.speak(utterance)
            return .nilValue
        }
        define("stop-speaking") { _, _ in
            speechSynthesizer.stopSpeaking(at: .immediate)
            return .nilValue
        }
        define("spell-check") { args, _ in
            guard let first = args.first, case .string(let text) = first else {
                throw LispError("spell-check: 文字列が必要です")
            }
            var language = "en"
            if args.count >= 2, case .string(let lang) = args[1] {
                language = lang
            }
            let checker = UITextChecker()
            let nsText = text as NSString
            var misspelled: [LispValue] = []
            var offset = 0
            while offset < nsText.length {
                let range = checker.rangeOfMisspelledWord(
                    in: text,
                    range: NSRange(location: offset, length: nsText.length - offset),
                    startingAt: offset,
                    wrap: false,
                    language: language
                )
                if range.location == NSNotFound { break }
                misspelled.append(.string(nsText.substring(with: range)))
                offset = NSMaxRange(range)
            }
            return .list(misspelled)
        }
        define("show-dictionary") { args, _ in
            guard let first = args.first, case .string(let word) = first else {
                throw LispError("show-dictionary: 文字列が必要です")
            }
            present(.dictionary(word: word))
            return .nilValue
        }

        // MARK: 共有・出力

        define("share") { args, _ in
            guard let first = args.first, case .string(let text) = first else {
                throw LispError("share: 文字列が必要です")
            }
            present(.share(text: text))
            return .nilValue
        }
        define("print-text") { args, _ in
            guard let first = args.first, case .string(let text) = first else {
                throw LispError("print-text: 文字列が必要です")
            }
            present(.print(text: text))
            return .nilValue
        }
        define("open-url") { args, _ in
            guard let first = args.first, case .string(let urlString) = first else {
                throw LispError("open-url: 文字列が必要です")
            }
            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" || scheme == "mailto" else {
                throw LispError("open-url: http(s)/mailto の URL が必要です: \(urlString)")
            }
            present(.openURL(url: url))
            return .nilValue
        }

        // MARK: その他

        define("haptic") { args, _ in
            var kind = "light"
            if let first = args.first, case .symbol(let sym) = first {
                kind = sym
            } else if let first = args.first, case .string(let str) = first {
                kind = str
            }
            switch kind {
            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return .nilValue
        }
    }

    /// ピッカー系(応答待ちが必要なため、ダイアログと同様にセマフォで待つ)。
    /// 専用スレッドから呼ばれる前提。
    static func installPickers(
        into interpreter: LispInterpreter,
        present: @escaping (MacroPlatformRequest) -> Void
    ) {
        let globals = interpreter.globals

        globals.define("pick-file", .builtin(LispBuiltin("pick-file") { _, itp in
            guard !Thread.isMainThread else {
                throw LispError("pick-file はコマンド実行中にのみ使えます")
            }
            let semaphore = DispatchSemaphore(value: 0)
            var response = LispValue.nilValue
            let started = Date()
            DispatchQueue.main.async {
                present(.pickFile { value in
                    response = value
                    semaphore.signal()
                })
            }
            semaphore.wait()
            itp.extendDeadline(by: Date().timeIntervalSince(started))
            return response
        }))

        globals.define("export-text", .builtin(LispBuiltin("export-text") { args, _ in
            guard args.count == 2,
                  case .string(let filename) = args[0],
                  case .string(let text) = args[1] else {
                throw LispError("export-text: (export-text ファイル名 文字列) の形式で指定してください")
            }
            DispatchQueue.main.async {
                present(.exportText(filename: filename, text: text))
            }
            return .nilValue
        }))
    }
}
