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

/// メインスレッドで実行するヘルパ(登録コールバックはマクロスレッドからも呼ばれる)
private func onMain(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
        body()
    } else {
        DispatchQueue.main.async(execute: body)
    }
}

/// ドキュメントピッカーの結果を 1 回だけ受け取るデリゲート
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL?) -> Void
    private var finished = false

    init(onPick: @escaping (URL?) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        onPick(url)
    }
}

private extension UITextView {
    /// 共有シートのポップオーバー基点にする選択矩形(なければビュー中央)
    func selectionRect() -> CGRect {
        if let range = selectedTextRange {
            let rects = selectionRects(for: range)
            if let first = rects.first?.rect, first.width > 0 || first.height > 0 {
                return first
            }
            return caretRect(for: range.end)
        }
        return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    }
}

/// マクロ機能の中核。Macros フォルダの .lsp を読み込み、
/// define-command されたコマンドを保持・実行する(文書ごとに 1 つ)。
/// API はメインスレッドから呼ぶこと。マクロ本体は専用スレッドで実行される。
final class MacroEngine: ObservableObject {
    @Published private(set) var commands: [MacroCommand] = []
    @Published private(set) var selectionCommands: [MacroCommand] = []
    @Published var errorMessage: String?
    @Published var replLines: [REPLLine] = []
    @Published var toastMessage: String?
    @Published private(set) var isRunning = false

    /// 現在の文書のテキストビュー(EditorView が接続する)。
    /// proxy 自体は軽量で循環参照もないため強参照で保持する(textView は proxy 内で weak)
    var proxy: TextViewProxy?
    var documentName: () -> String = { "" }
    /// ダイアログの表示方法(テストで差し替え可能。nil なら UIAlertController)
    var dialogPresenter: ((MacroDialogRequest, @escaping (LispValue) -> Void) -> Void)?

    private var interpreter = LispInterpreter()
    private let macrosDirectory: URL
    private let filesDirectory: URL
    private var loaded = false
    /// ピッカー表示中のデリゲート保持(閉じるまで生存させる)
    private var pickerCoordinator: DocumentPickerCoordinator?

    /// マクロ実行スレッドのスタックサイズ。深度上限に達する前にスタックが
    /// 尽きないよう大きめに確保する(仮想メモリのため実際の使用分しかコミットされない)
    private static let executionStackSize = 64 * 1024 * 1024
    /// 専用スレッド前提の評価深度上限
    private static let executionMaxDepth = 2500

    /// - Parameters:
    ///   - directory: マクロ置き場(テスト用の差し替え。nil なら Documents/Macros)
    ///   - filesDirectory: file-* API の基点(nil なら Documents)
    init(directory: URL? = nil, filesDirectory: URL? = nil) {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        macrosDirectory = directory ?? documents.appendingPathComponent("Macros", isDirectory: true)
        self.filesDirectory = filesDirectory ?? directory?.deletingLastPathComponent() ?? documents
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
    func run(_ command: MacroCommand, completion: (() -> Void)? = nil) {
        execute(label: command.name, completion: completion) { interpreter in
            _ = try interpreter.apply(command.function, [])
        }
    }

    /// 選択範囲クイック適用: 関数に選択文字列を渡し、返った文字列で置き換える
    func runSelection(_ command: MacroCommand, completion: (() -> Void)? = nil) {
        guard let textView = proxy?.textView,
              let range = textView.selectedTextRange, !range.isEmpty else {
            completion?()
            return
        }
        let selected = textView.text(in: range) ?? ""
        execute(label: command.name, completion: completion) { interpreter in
            let result = try interpreter.apply(command.function, [.string(selected)])
            if case .string(let replacement) = result {
                try LispEditorAPI.runOnMain {
                    textView.replace(range, withText: replacement)
                }
            }
        }
    }

    /// REPL: 式を評価して結果(またはエラー)を履歴に追加する
    func evalREPL(_ source: String, completion: (() -> Void)? = nil) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?()
            return
        }
        replLines.append(REPLLine(kind: .input, text: "> " + trimmed))
        execute(label: "REPL", reportErrorsToREPL: true, completion: completion) { interpreter in
            let result = try interpreter.run(trimmed)
            DispatchQueue.main.async {
                self.replLines.append(REPLLine(kind: .output, text: "=> " + result.printed()))
            }
        }
    }

    /// マクロを専用スレッド(大きなスタック)で実行する。
    /// 実行中は isRunning が立ち、二重実行は拒否する。
    /// 1 回の実行を 1 つの Undo 単位にまとめ、終了時にバインディングへ同期する。
    private func execute(
        label: String,
        reportErrorsToREPL: Bool = false,
        completion: (() -> Void)?,
        _ body: @escaping (LispInterpreter) throws -> Void
    ) {
        guard !isRunning else {
            errorMessage = "別のマクロを実行中です"
            completion?()
            return
        }
        isRunning = true
        let textView = proxy?.textView
        textView?.undoManager?.beginUndoGrouping()

        let interpreter = self.interpreter
        let thread = Thread { [weak self] in
            var caught: Error?
            do {
                try body(interpreter)
            } catch {
                caught = error
            }
            DispatchQueue.main.async {
                guard let self else { return }
                textView?.undoManager?.endUndoGrouping()
                if let textView {
                    // 編集結果をドキュメント(SwiftUI バインディング)へ確実に同期する
                    textView.delegate?.textViewDidChange?(textView)
                }
                if let caught {
                    if reportErrorsToREPL {
                        self.replLines.append(REPLLine(kind: .error, text: "エラー: \(caught)"))
                    } else {
                        self.errorMessage = "\(label): \(caught)"
                    }
                }
                self.isRunning = false
                completion?()
            }
        }
        thread.name = "MacroExecution"
        thread.stackSize = Self.executionStackSize
        thread.start()
    }

    // MARK: - 内部

    private func installBuiltins() {
        interpreter.maxDepth = Self.executionMaxDepth
        LispEditorAPI.install(
            into: interpreter,
            textView: { [weak self] in self?.proxy?.textView },
            documentName: { [weak self] in self?.documentName() ?? "" },
            message: { [weak self] text in
                onMain { self?.toastMessage = text }
            }
        )
        LispSystemAPI.install(
            into: interpreter,
            filesDirectory: filesDirectory,
            presentDialog: { [weak self] request, completion in
                guard let self else {
                    completion(.nilValue)
                    return
                }
                if let custom = self.dialogPresenter {
                    custom(request, completion)
                } else {
                    self.presentDefaultDialog(request, completion)
                }
            }
        )
        LispPlatformAPI.install(into: interpreter) { [weak self] request in
            self?.handlePlatformRequest(request)
        }
        LispPlatformAPI.installPickers(into: interpreter) { [weak self] request in
            self?.handlePlatformRequest(request)
        }
        // (format t ...) の出力は REPL コンソールへ
        interpreter.output = { [weak self] text in
            onMain { self?.replLines.append(REPLLine(kind: .output, text: text)) }
        }

        // コマンド登録(要件 §5.5)
        interpreter.globals.define(
            "define-command",
            .builtin(LispBuiltin("define-command") { [weak self] args, _ in
                guard args.count == 2, case .string(let name) = args[0] else {
                    throw LispError("define-command: (define-command \"名前\" 関数) の形式で指定してください")
                }
                onMain { self?.commands.append(MacroCommand(name: name, function: args[1])) }
                return .nilValue
            })
        )
        interpreter.globals.define(
            "define-selection-command",
            .builtin(LispBuiltin("define-selection-command") { [weak self] args, _ in
                guard args.count == 2, case .string(let name) = args[0] else {
                    throw LispError("define-selection-command: (define-selection-command \"名前\" 関数) の形式で指定してください")
                }
                onMain { self?.selectionCommands.append(MacroCommand(name: name, function: args[1])) }
                return .nilValue
            })
        )
    }

    /// テストが差し替えられるプラットフォーム連携ハンドラ(nil なら実 UI を提示)
    var platformHandler: ((MacroPlatformRequest) -> Void)?

    /// iPadOS 連携要求を UI として提示する(メインスレッドで呼ばれる)
    private func handlePlatformRequest(_ request: MacroPlatformRequest) {
        if let handler = platformHandler {
            handler(request)
            return
        }
        guard let textView = proxy?.textView,
              var presenter = textView.window?.rootViewController else {
            if case .pickFile(let completion) = request { completion(.nilValue) }
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        switch request {
        case .share(let text):
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = textView
            vc.popoverPresentationController?.sourceRect = textView.selectionRect()
            presenter.present(vc, animated: true)

        case .print(let text):
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = documentName()
            controller.printInfo = info
            let formatter = UISimpleTextPrintFormatter(text: text)
            formatter.font = .systemFont(ofSize: 12)
            controller.printFormatter = formatter
            controller.present(animated: true)

        case .dictionary(let word):
            let vc = UIReferenceLibraryViewController(term: word)
            presenter.present(vc, animated: true)

        case .openURL(let url):
            UIApplication.shared.open(url)

        case .pickFile(let completion):
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.text, .plainText, .sourceCode]
            )
            let coordinator = DocumentPickerCoordinator { url in
                guard let url else {
                    completion(.nilValue)
                    return
                }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    completion(.string(text))
                } else {
                    completion(.nilValue)
                }
            }
            picker.delegate = coordinator
            pickerCoordinator = coordinator
            presenter.present(picker, animated: true)

        case .exportText(let filename, let text):
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            let picker = UIDocumentPickerViewController(forExporting: [url])
            presenter.present(picker, animated: true)
        }
    }

    /// 既定のダイアログ実装(UIAlertController)。メインスレッドで呼ばれる
    private func presentDefaultDialog(
        _ request: MacroDialogRequest,
        _ completion: @escaping (LispValue) -> Void
    ) {
        guard var presenter = proxy?.textView?.window?.rootViewController else {
            completion(.nilValue)
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        switch request {
        case .alert(let message):
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                completion(.nilValue)
            })
            presenter.present(alert, animated: true)
        case .confirm(let message):
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                completion(.nilValue)
            })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                completion(.t)
            })
            presenter.present(alert, animated: true)
        case .prompt(let message, let defaultText):
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = defaultText
            }
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                completion(.nilValue)
            })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak alert] _ in
                completion(.string(alert?.textFields?.first?.text ?? ""))
            })
            presenter.present(alert, animated: true)
        }
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
        ("read-aloud.lsp", """
        ;; 文書の内容を読み上げます(校正に便利)
        (define-command "読み上げる"
          (lambda () (speak (buffer-text))))

        (define-command "読み上げを止める"
          (lambda () (stop-speaking)))
        """),
        ("share-document.lsp", """
        ;; 文書を他のアプリに共有します
        (define-command "共有する"
          (lambda () (share (buffer-text))))
        """),
    ]
}
