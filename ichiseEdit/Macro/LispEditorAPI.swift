import UIKit

/// マクロから現在の文書を操作するためのエディタ API(要件 §5.1〜5.2)。
/// 位置はすべて文字(グラフェム)単位のオフセットで受け渡しする。
/// 編集は UITextView の編集経路(replace / insertText)を通すため Undo 可能。
enum LispEditorAPI {

    /// - Parameters:
    ///   - textView: 現在の文書のテキストビュー(閉じられた後は nil)
    ///   - documentName: ファイル名を返すクロージャ
    static func install(
        into interpreter: LispInterpreter,
        textView: @escaping () -> UITextView?,
        documentName: @escaping () -> String
    ) {
        let globals = interpreter.globals

        func define(_ name: String, _ body: @escaping ([LispValue], LispInterpreter) throws -> LispValue) {
            globals.define(name, .builtin(LispBuiltin(name, body)))
        }

        func requireTextView() throws -> UITextView {
            guard let view = textView() else {
                throw LispError("編集中の文書がありません")
            }
            return view
        }

        // MARK: バッファ

        define("buffer-text") { _, _ in
            .string(try requireTextView().text ?? "")
        }
        define("set-buffer-text") { args, _ in
            guard args.count == 1, case .string(let newText) = args[0] else {
                throw LispError("set-buffer-text: 文字列が必要です")
            }
            let view = try requireTextView()
            try replaceCharacterRange(view, 0, (view.text ?? "").count, with: newText)
            return .nilValue
        }
        define("buffer-substring") { args, _ in
            guard args.count == 2,
                  case .integer(let start) = args[0],
                  case .integer(let end) = args[1] else {
                throw LispError("buffer-substring: (buffer-substring 開始 終了) の形式で指定してください")
            }
            let text = try requireTextView().text ?? ""
            guard start >= 0, end <= text.count, start <= end else {
                throw LispError("buffer-substring: 範囲外です")
            }
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(text.startIndex, offsetBy: end)
            return .string(String(text[from..<to]))
        }
        define("buffer-length") { _, _ in
            .integer((try requireTextView().text ?? "").count)
        }
        define("buffer-name") { _, _ in
            .string(documentName())
        }
        define("char-count") { _, _ in
            .integer((try requireTextView().text ?? "").count)
        }
        define("line-count") { _, _ in
            let text = try requireTextView().text ?? ""
            return .integer(TextStatistics(counting: text).lines)
        }

        // MARK: カーソル・選択

        define("point") { _, _ in
            let view = try requireTextView()
            return .integer(characterOffset(view, utf16: view.selectedRange.location))
        }
        define("goto-char") { args, _ in
            guard args.count == 1, case .integer(let pos) = args[0] else {
                throw LispError("goto-char: 位置(整数)が必要です")
            }
            let view = try requireTextView()
            let utf16 = try utf16Offset(view, character: pos)
            view.selectedRange = NSRange(location: utf16, length: 0)
            return .integer(pos)
        }
        define("selection-start") { _, _ in
            let view = try requireTextView()
            return .integer(characterOffset(view, utf16: view.selectedRange.location))
        }
        define("selection-end") { _, _ in
            let view = try requireTextView()
            let range = view.selectedRange
            return .integer(characterOffset(view, utf16: range.location + range.length))
        }
        define("set-selection") { args, _ in
            guard args.count == 2,
                  case .integer(let start) = args[0],
                  case .integer(let end) = args[1], start <= end else {
                throw LispError("set-selection: (set-selection 開始 終了) の形式で指定してください")
            }
            let view = try requireTextView()
            let from = try utf16Offset(view, character: start)
            let to = try utf16Offset(view, character: end)
            view.selectedRange = NSRange(location: from, length: to - from)
            return .nilValue
        }
        define("selected-text") { _, _ in
            let view = try requireTextView()
            let range = view.selectedRange
            guard range.length > 0 else { return .nilValue }
            return .string(((view.text ?? "") as NSString).substring(with: range))
        }
        define("replace-selection") { args, _ in
            guard args.count == 1, case .string(let replacement) = args[0] else {
                throw LispError("replace-selection: 文字列が必要です")
            }
            let view = try requireTextView()
            guard let selection = view.selectedTextRange else {
                throw LispError("選択範囲がありません")
            }
            view.replace(selection, withText: replacement)
            return .nilValue
        }

        // MARK: 編集

        define("insert") { args, _ in
            guard args.count == 1, case .string(let s) = args[0] else {
                throw LispError("insert: 文字列が必要です")
            }
            try requireTextView().insertText(s)
            return .nilValue
        }
        define("delete-region") { args, _ in
            guard args.count == 2,
                  case .integer(let start) = args[0],
                  case .integer(let end) = args[1], start <= end else {
                throw LispError("delete-region: (delete-region 開始 終了) の形式で指定してください")
            }
            let view = try requireTextView()
            try replaceCharacterRange(view, start, end, with: "")
            return .nilValue
        }

        // MARK: 検索・置換

        define("search-forward") { args, _ in
            guard let first = args.first, case .string(let pattern) = first else {
                throw LispError("search-forward: 検索文字列が必要です")
            }
            let text = try requireTextView().text ?? ""
            var startIndex = text.startIndex
            if args.count >= 2 {
                guard case .integer(let from) = args[1], from >= 0, from <= text.count else {
                    throw LispError("search-forward: 開始位置が範囲外です")
                }
                startIndex = text.index(text.startIndex, offsetBy: from)
            }
            guard let found = text.range(of: pattern, range: startIndex..<text.endIndex) else {
                return .nilValue
            }
            return .integer(text.distance(from: text.startIndex, to: found.lowerBound))
        }
        define("replace-all") { args, _ in
            guard args.count == 2,
                  case .string(let from) = args[0],
                  case .string(let to) = args[1], !from.isEmpty else {
                throw LispError("replace-all: (replace-all 検索 置換) の形式で指定してください")
            }
            let view = try requireTextView()
            let text = view.text ?? ""
            let count = text.components(separatedBy: from).count - 1
            if count > 0 {
                let replaced = text.replacingOccurrences(of: from, with: to)
                try replaceCharacterRange(view, 0, text.count, with: replaced)
            }
            return .integer(count)
        }
        define("re-replace-all") { args, _ in
            guard args.count == 2,
                  case .string(let pattern) = args[0],
                  case .string(let template) = args[1] else {
                throw LispError("re-replace-all: (re-replace-all 正規表現 置換) の形式で指定してください")
            }
            // ^ と $ が各行の行頭・行末にマッチするようにする(テキスト編集での実用性)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                throw LispError("re-replace-all: 正規表現が不正です: \(pattern)")
            }
            let view = try requireTextView()
            let text = view.text ?? ""
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let count = regex.numberOfMatches(in: text, range: fullRange)
            if count > 0 {
                let replaced = regex.stringByReplacingMatches(
                    in: text, range: fullRange, withTemplate: template
                )
                try replaceCharacterRange(view, 0, text.count, with: replaced)
            }
            return .integer(count)
        }
    }

    // MARK: - 位置変換・編集ヘルパ

    private static func utf16Offset(_ view: UITextView, character: Int) throws -> Int {
        let text = view.text ?? ""
        guard character >= 0, character <= text.count else {
            throw LispError("位置が範囲外です: \(character)")
        }
        return text.index(text.startIndex, offsetBy: character).utf16Offset(in: text)
    }

    private static func characterOffset(_ view: UITextView, utf16: Int) -> Int {
        let text = view.text ?? ""
        let clamped = min(max(0, utf16), (text as NSString).length)
        guard let index = String.Index(utf16Offset: clamped, in: text) as String.Index? else {
            return 0
        }
        return text.distance(from: text.startIndex, to: index)
    }

    /// 文字オフセット範囲を UITextRange に変換し、Undo 可能な編集経路で置換する
    private static func replaceCharacterRange(
        _ view: UITextView,
        _ start: Int,
        _ end: Int,
        with replacement: String
    ) throws {
        let text = view.text ?? ""
        guard start >= 0, end <= text.count, start <= end else {
            throw LispError("範囲外です: \(start)..\(end)")
        }
        let fromUTF16 = try utf16Offset(view, character: start)
        let toUTF16 = try utf16Offset(view, character: end)
        guard let from = view.position(from: view.beginningOfDocument, offset: fromUTF16),
              let to = view.position(from: view.beginningOfDocument, offset: toUTF16),
              let range = view.textRange(from: from, to: to) else {
            throw LispError("編集範囲を解決できません")
        }
        view.replace(range, withText: replacement)
    }
}
