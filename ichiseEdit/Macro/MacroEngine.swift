import UIKit
import SwiftUI

/// マクロメニューに登録されたコマンド
struct MacroCommand: Identifiable {
    let id = UUID()
    let name: String
    let function: LispValue
}

/// REPL コンソールの 1 行
struct REPLLine: Identifiable {
    enum Kind {
        case input
        case output
        case error
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

/// マクロ機能の中核。Macros フォルダの .lsp を読み込み、
/// define-command されたコマンドを保持・実行する(文書ごとに 1 つ)。
/// メインスレッドから使うこと(エディタ操作を伴うため)。
final class MacroEngine: ObservableObject {
    @Published private(set) var commands: [MacroCommand] = []
    @Published private(set) var selectionCommands: [MacroCommand] = []
    @Published var errorMessage: String?
    @Published var replLines: [REPLLine] = []
    @Published var toastMessage: String?

    /// 現在の文書のテキストビュー(EditorView が接続する)。
    /// proxy 自体は軽量で循環参照もないため強参照で保持する(textView は proxy 内で weak)
    var proxy: TextViewProxy?
    var documentName: () -> String = { "" }

    private var interpreter = LispInterpreter()
    private let macrosDirectory: URL
    private var loaded = false

    /// - Parameter directory: テスト用の差し替え。nil なら Documents/Macros
    init(directory: URL? = nil) {
        if let directory {
            macrosDirectory = directory
        } else {
            let documents = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            )[0]
            macrosDirectory = documents.appendingPathComponent("Macros", isDirectory: true)
        }
    }

    /// 初回のみ読み込む(EditorView の onAppear から呼ぶ)
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    /// Macros フォルダを読み直す(初回はサンプルマクロを配置する)
    func reload() {
        commands = []
        selectionCommands = []
        interpreter = LispInterpreter()
        installBuiltins()
        prepareDirectoryWithSamplesIfNeeded()

        let files = (try? FileManager.default.contentsOfDirectory(
            at: macrosDirectory, includingPropertiesForKeys: nil
        )) ?? []
        var loadErrors: [String] = []
        for file in files.filter({ $0.pathExtension.lowercased() == "lsp" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                _ = try interpreter.run(source)
            } catch {
                loadErrors.append("\(file.lastPathComponent): \(error)")
            }
        }
        if !loadErrors.isEmpty {
            errorMessage = "マクロの読み込みに失敗しました:\n" + loadErrors.joined(separator: "\n")
        }
    }

    /// メニューのコマンドを実行する(1 回の実行 = 1 つの Undo 単位)
    func run(_ command: MacroCommand) {
        guard let textView = proxy?.textView else { return }
        withUndoGroup(textView) {
            do {
                _ = try interpreter.apply(command.function, [])
            } catch {
                errorMessage = "\(command.name): \(error)"
            }
        }
    }

    /// 選択範囲クイック適用: 関数に選択文字列を渡し、返った文字列で置き換える
    func runSelection(_ command: MacroCommand) {
        guard let textView = proxy?.textView,
              let range = textView.selectedTextRange, !range.isEmpty else { return }
        let selected = textView.text(in: range) ?? ""
        withUndoGroup(textView) {
            do {
                let result = try interpreter.apply(command.function, [.string(selected)])
                if case .string(let replacement) = result {
                    textView.replace(range, withText: replacement)
                }
            } catch {
                errorMessage = "\(command.name): \(error)"
            }
        }
    }

    /// REPL: 式を評価して結果(またはエラー)を履歴に追加する
    func evalREPL(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replLines.append(REPLLine(kind: .input, text: "> " + trimmed))

        let textView = proxy?.textView
        textView?.undoManager?.beginUndoGrouping()
        defer {
            textView?.undoManager?.endUndoGrouping()
            if let textView {
                textView.delegate?.textViewDidChange?(textView)
            }
        }
        do {
            let result = try interpreter.run(trimmed)
            replLines.append(REPLLine(kind: .output, text: "=> " + result.printed()))
        } catch {
            replLines.append(REPLLine(kind: .error, text: "エラー: \(error)"))
        }
    }

    private func withUndoGroup(_ textView: UITextView, _ body: () -> Void) {
        textView.undoManager?.beginUndoGrouping()
        defer {
            textView.undoManager?.endUndoGrouping()
            // 編集結果をドキュメント(SwiftUI バインディング)へ確実に同期する
            textView.delegate?.textViewDidChange?(textView)
        }
        body()
    }

    // MARK: - 内部

    private func installBuiltins() {
        LispEditorAPI.install(
            into: interpreter,
            textView: { [weak self] in self?.proxy?.textView },
            documentName: { [weak self] in self?.documentName() ?? "" },
            message: { [weak self] text in self?.toastMessage = text }
        )
        // (format t ...) の出力は REPL コンソールへ
        interpreter.output = { [weak self] text in
            self?.replLines.append(REPLLine(kind: .output, text: text))
        }

        // コマンド登録(要件 §5.5)
        interpreter.globals.define(
            "define-command",
            .builtin(LispBuiltin("define-command") { [weak self] args, _ in
                guard args.count == 2, case .string(let name) = args[0] else {
                    throw LispError("define-command: (define-command \"名前\" 関数) の形式で指定してください")
                }
                self?.commands.append(MacroCommand(name: name, function: args[1]))
                return .nilValue
            })
        )
        interpreter.globals.define(
            "define-selection-command",
            .builtin(LispBuiltin("define-selection-command") { [weak self] args, _ in
                guard args.count == 2, case .string(let name) = args[0] else {
                    throw LispError("define-selection-command: (define-selection-command \"名前\" 関数) の形式で指定してください")
                }
                self?.selectionCommands.append(MacroCommand(name: name, function: args[1]))
                return .nilValue
            })
        )
    }

    private func prepareDirectoryWithSamplesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: macrosDirectory, withIntermediateDirectories: true)
        // 新しいバージョンで追加されたサンプルにも対応できるよう、ファイル単位で配置する
        for (fileName, source) in Self.sampleMacros {
            let url = macrosDirectory.appendingPathComponent(fileName)
            guard !fm.fileExists(atPath: url.path) else { continue }
            try? source.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 初回起動時に Macros フォルダへ配置するサンプル(書き方の手本を兼ねる)
    static let sampleMacros: [(String, String)] = [
        ("sort-lines.lsp", """
        ;; 全行をソートして並べ替えます
        (define-command "行をソート"
          (lambda ()
            (set-buffer-text
              (string-join (sort (string-split (buffer-text) "\\n")) "\\n"))))
        """),
        ("dedupe-lines.lsp", """
        ;; 重複した行を取り除きます(最初の出現を残します)
        (define-command "重複行を削除"
          (lambda ()
            (let ((lines (string-split (buffer-text) "\\n"))
                  (seen nil)
                  (result nil))
              (while (consp lines)
                (if (member (car lines) seen)
                    nil
                    (progn
                      (setq seen (cons (car lines) seen))
                      (setq result (cons (car lines) result))))
                (setq lines (cdr lines)))
              (set-buffer-text (string-join (reverse result) "\\n")))))
        """),
        ("trim-trailing-spaces.lsp", """
        ;; 各行の行末にある空白を取り除きます
        (define-command "行末の空白を削除"
          (lambda ()
            (re-replace-all "[ \\t]+$" "")))
        """),
        ("insert-date.lsp", """
        ;; カーソル位置に今日の日付を挿入します
        (define-command "日付を挿入"
          (lambda ()
            (insert (current-date-string "yyyy-MM-dd"))))
        """),
        ("selection-tools.lsp", """
        ;; テキスト選択中のメニューに表示されるコマンド
        (define-selection-command "大文字にする"
          (lambda (text) (string-upcase text)))

        (define-selection-command "「」で囲む"
          (lambda (text) (string-append "「" text "」")))
        """),
    ]
}
