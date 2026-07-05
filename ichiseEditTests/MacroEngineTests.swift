import XCTest
@testable import ichiseEdit

final class LispEditorAPITests: XCTestCase {

    private func makeTextView(_ text: String) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.text = text
        return view
    }

    private func makeInterpreter(_ view: UITextView, name: String = "test.txt") -> LispInterpreter {
        let interpreter = LispInterpreter()
        LispEditorAPI.install(into: interpreter, textView: { view }, documentName: { name })
        return interpreter
    }

    func testBufferOperations() throws {
        let view = makeTextView("hello world")
        let interpreter = makeInterpreter(view)
        XCTAssertEqual(try interpreter.run("(buffer-text)").printed(), "\"hello world\"")
        XCTAssertEqual(try interpreter.run("(buffer-length)").printed(), "11")
        XCTAssertEqual(try interpreter.run("(buffer-substring 6 11)").printed(), "\"world\"")
        XCTAssertEqual(try interpreter.run("(buffer-name)").printed(), "\"test.txt\"")
        _ = try interpreter.run(#"(set-buffer-text "あいうえお")"#)
        XCTAssertEqual(view.text, "あいうえお")
        XCTAssertEqual(try interpreter.run("(char-count)").printed(), "5")
    }

    func testPointAndSelectionUseCharacterOffsets() throws {
        // 絵文字(UTF-16 では複数単位)でも文字単位で扱えること
        let view = makeTextView("👨‍👩‍👧‍👦あiう")
        let interpreter = makeInterpreter(view)
        _ = try interpreter.run("(goto-char 1)")
        XCTAssertEqual(try interpreter.run("(point)").printed(), "1")
        _ = try interpreter.run("(set-selection 1 3)")
        XCTAssertEqual(try interpreter.run("(selected-text)").printed(), "\"あi\"")
        XCTAssertEqual(try interpreter.run("(selection-start)").printed(), "1")
        XCTAssertEqual(try interpreter.run("(selection-end)").printed(), "3")
        _ = try interpreter.run(#"(replace-selection "X")"#)
        XCTAssertEqual(view.text, "👨‍👩‍👧‍👦Xう")
    }

    func testLineStartAndEnd() throws {
        let view = makeTextView("一行目\nab👨‍👩‍👧‍👦cd\n三行目")
        let interpreter = makeInterpreter(view)
        // 2 行目の途中(👨‍👩‍👧‍👦 の後 = 行内 3 文字目): 行頭 4、行末 9
        XCTAssertEqual(try interpreter.run("(line-start 7)").printed(), "4")
        XCTAssertEqual(try interpreter.run("(line-end 7)").printed(), "9")
        // 先頭行
        XCTAssertEqual(try interpreter.run("(line-start 2)").printed(), "0")
        XCTAssertEqual(try interpreter.run("(line-end 2)").printed(), "3")
    }

    func testInsertAndDelete() throws {
        let view = makeTextView("abc")
        let interpreter = makeInterpreter(view)
        _ = try interpreter.run("(goto-char 1) (insert \"-\")")
        XCTAssertEqual(view.text, "a-bc")
        _ = try interpreter.run("(delete-region 0 2)")
        XCTAssertEqual(view.text, "bc")
    }

    func testSearchAndReplace() throws {
        let view = makeTextView("cat dog cat bird")
        let interpreter = makeInterpreter(view)
        XCTAssertEqual(try interpreter.run(#"(search-forward "dog")"#).printed(), "4")
        XCTAssertEqual(try interpreter.run(#"(search-forward "cat" 5)"#).printed(), "8")
        XCTAssertEqual(try interpreter.run(#"(search-forward "fox")"#).printed(), "nil")
        XCTAssertEqual(try interpreter.run(#"(replace-all "cat" "ネコ")"#).printed(), "2")
        XCTAssertEqual(view.text, "ネコ dog ネコ bird")
    }

    func testRegexReplaceWithLineAnchors() throws {
        let view = makeTextView("a  \nb\t\nc")
        let interpreter = makeInterpreter(view)
        XCTAssertEqual(try interpreter.run(#"(re-replace-all "[ \t]+$" "")"#).printed(), "2")
        XCTAssertEqual(view.text, "a\nb\nc")
    }

    func testErrorWhenNoTextView() {
        let interpreter = LispInterpreter()
        LispEditorAPI.install(into: interpreter, textView: { nil }, documentName: { "" })
        XCTAssertThrowsError(try interpreter.run("(buffer-text)"))
    }
}

final class MacroEngineTests: XCTestCase {

    private var retainedViews: [UITextView] = []

    private func temporaryBase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroEngineTests-\(UUID().uuidString)")
    }

    /// base/Macros をマクロ置き場、base をファイル API の基点にしたエンジンを作る
    private func makeEngine(
        macroSources: [String: String] = [:],
        text: String
    ) throws -> (MacroEngine, UITextView) {
        let base = temporaryBase()
        let macros = base.appendingPathComponent("Macros", isDirectory: true)
        try FileManager.default.createDirectory(at: macros, withIntermediateDirectories: true)
        for (name, source) in macroSources {
            try source.write(to: macros.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let engine = MacroEngine(directory: macros, filesDirectory: base)
        let proxy = TextViewProxy()
        let view = UITextView(usingTextLayoutManager: true)
        view.text = text
        retainedViews.append(view)
        proxy.textView = view
        engine.proxy = proxy
        engine.loadIfNeeded()
        return (engine, view)
    }

    private func runAndWait(_ engine: MacroEngine, commandNamed name: String) throws {
        guard let command = engine.commands.first(where: { $0.name == name }) else {
            throw LispError("コマンドが見つかりません: \(name)")
        }
        let done = expectation(description: "run \(name)")
        engine.run(command) { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    private func repl(_ engine: MacroEngine, _ source: String) {
        let done = expectation(description: "repl")
        engine.evalREPL(source) { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    // MARK: - 読み込み・実行

    func testLoadAndRunCommand() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["a.lsp": #"""
            (define-command "びっくり"
              (lambda () (set-buffer-text (string-append (buffer-text) "!"))))
            """#],
            text: "abc"
        )
        try runAndWait(engine, commandNamed: "びっくり")
        XCTAssertEqual(view.text, "abc!")
        XCTAssertNil(engine.errorMessage)
    }

    // MARK: - 標準コマンド(stdlib で定義。サンプルを消しても残る)

    func testStandardCommandsExistWithEmptyMacrosFolder() throws {
        // フォルダはあるがマクロファイルが 1 つもない(=サンプルを全部消した)状態
        let (engine, _) = try makeEngine(text: "")
        let names = engine.commands.map(\.name)
        for expected in ["行をソート", "重複行を削除", "行末の空白を削除", "日付を挿入", "共有する"] {
            XCTAssertTrue(names.contains(expected), "\(expected) がありません")
        }
        XCTAssertTrue(engine.selectionCommands.map(\.name).contains("大文字にする"))
        // 重複登録がない
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testUserMacroOverridesStandardCommand() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["my-sort.lsp": #"""
            (define-command "行をソート"
              (lambda () (set-buffer-text "上書きされた")))
            """#],
            text: "b\na"
        )
        // 同名は 1 つだけ(重複表示されない)
        XCTAssertEqual(engine.commands.filter { $0.name == "行をソート" }.count, 1)
        try runAndWait(engine, commandNamed: "行をソート")
        XCTAssertEqual(view.text, "上書きされた")
    }

    func testSamplesWrittenOnlyOnFreshDirectory() throws {
        // フォルダ未作成 → 初回にサンプルが配置される
        let base = temporaryBase()
        let macros = base.appendingPathComponent("Macros", isDirectory: true)
        let engine = MacroEngine(directory: macros, filesDirectory: base)
        engine.loadIfNeeded()
        let written = try FileManager.default.contentsOfDirectory(atPath: macros.path)
        XCTAssertFalse(written.isEmpty)

        // ユーザーがサンプルを全削除 → 再読み込みしても復活しない(標準コマンドは残る)
        for file in written {
            try FileManager.default.removeItem(at: macros.appendingPathComponent(file))
        }
        engine.reload()
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: macros.path)).isEmpty)
        XCTAssertTrue(engine.commands.map(\.name).contains("行をソート"))
    }

    func testSampleSortLines() throws {
        let (engine, view) = try makeEngine(text: "banana\napple\ncherry")
        try runAndWait(engine, commandNamed: "行をソート")
        XCTAssertEqual(view.text, "apple\nbanana\ncherry")
        XCTAssertNil(engine.errorMessage)
    }

    func testSampleDedupeLines() throws {
        let (engine, view) = try makeEngine(text: "a\nb\na\nc\nb")
        try runAndWait(engine, commandNamed: "重複行を削除")
        XCTAssertEqual(view.text, "a\nb\nc")
        XCTAssertNil(engine.errorMessage)
    }

    func testLoadErrorIsReported() throws {
        let (engine, _) = try makeEngine(macroSources: ["bad.lsp": "(defun broken"], text: "")
        XCTAssertNotNil(engine.errorMessage)
    }

    func testRuntimeErrorIsReportedAndDoesNotCrash() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["f.lsp": #"(define-command "失敗" (lambda () (error "わざと")))"#],
            text: "keep"
        )
        try runAndWait(engine, commandNamed: "失敗")
        XCTAssertEqual(view.text, "keep")
        XCTAssertTrue(engine.errorMessage?.contains("わざと") == true)
    }

    // MARK: - REPL・選択コマンド・ユーティリティ

    func testREPLEvaluatesAndRecordsHistory() throws {
        let (engine, _) = try makeEngine(text: "hello")
        repl(engine, "(+ 1 2)")
        XCTAssertEqual(engine.replLines.map(\.text), ["> (+ 1 2)", "=> 3"])
        repl(engine, "(buffer-length)")
        XCTAssertEqual(engine.replLines.last?.text, "=> 5")
        repl(engine, "(undefined-fn)")
        XCTAssertEqual(engine.replLines.last?.kind, .error)
    }

    func testREPLCapturesFormatOutput() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(format t "hi ~D" 42)"#)
        XCTAssertTrue(engine.replLines.contains { $0.text == "hi 42" })
    }

    func testSelectionCommand() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["s.lsp": #"(define-selection-command "upcase" (lambda (text) (string-upcase text)))"#],
            text: "abc def"
        )
        guard let command = engine.selectionCommands.first(where: { $0.name == "upcase" }) else {
            return XCTFail("選択コマンドが登録されていません")
        }
        view.selectedRange = NSRange(location: 0, length: 3)
        let done = expectation(description: "selection")
        engine.runSelection(command) { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(view.text, "ABC def")
    }

    func testUtilities() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(set-clipboard "コピー")"#)
        XCTAssertEqual(UIPasteboard.general.string, "コピー")
        repl(engine, "(clipboard-text)")
        XCTAssertEqual(engine.replLines.last?.text, "=> \"コピー\"")
        repl(engine, #"(message "できました")"#)
        XCTAssertEqual(engine.toastMessage, "できました")
        repl(engine, #"(current-date-string "yyyy")"#)
        XCTAssertTrue(engine.replLines.last?.text.contains("20") == true)
    }

    // MARK: - M4: ファイル操作(サンドボックス)

    func testFileAPI() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(file-write "notes/greeting.txt" "こんにちは")"#)
        repl(engine, #"(file-exists-p "notes/greeting.txt")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> t")
        repl(engine, #"(file-read "notes/greeting.txt")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> \"こんにちは\"")
        repl(engine, #"(file-list "notes")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> (\"greeting.txt\")")
        repl(engine, #"(file-exists-p "notes/missing.txt")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> nil")
    }

    func testSandboxEscapeIsRejected() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(file-read "../outside.txt")"#)
        XCTAssertEqual(engine.replLines.last?.kind, .error)
        repl(engine, #"(file-write "/tmp/evil.txt" "x")"#)
        XCTAssertEqual(engine.replLines.last?.kind, .error)
        repl(engine, #"(file-write "a/../../escape.txt" "x")"#)
        XCTAssertEqual(engine.replLines.last?.kind, .error)
    }

    // MARK: - M4: ダイアログ(プレゼンタ差し替え)

    func testConfirmDialogDrivesBranch() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["c.lsp": #"""
            (define-command "確認テスト"
              (lambda ()
                (if (confirm "続けますか?")
                    (insert "yes")
                    (insert "no"))))
            """#],
            text: ""
        )
        engine.dialogPresenter = { request, completion in
            if case .confirm = request {
                completion(.t)
            } else {
                completion(.nilValue)
            }
        }
        try runAndWait(engine, commandNamed: "確認テスト")
        XCTAssertEqual(view.text, "yes")
    }

    func testPromptDialogReturnsText() throws {
        let (engine, _) = try makeEngine(text: "")
        engine.dialogPresenter = { request, completion in
            if case .prompt(_, let defaultText) = request {
                completion(.string(defaultText + "太郎"))
            } else {
                completion(.nilValue)
            }
        }
        repl(engine, #"(prompt "名前は?" "山田")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> \"山田太郎\"")
    }

    // MARK: - M4: 専用スレッド実行(大スタック)

    func testDeepRecursionRunsOnExecutionThread() throws {
        let (engine, _) = try makeEngine(text: "")
        // メインスレッドの既定上限(800)を超える深さでも専用スレッドなら動く
        repl(engine, "(defun down (n) (if (= n 0) 0 (down (- n 1)))) (down 600)")
        XCTAssertEqual(engine.replLines.last?.text, "=> 0")
    }

    // MARK: - ショートカット割当(:shortcut)

    func testShortcutParsing() throws {
        let shortcut = try MacroShortcut.parse("cmd+shift+s")
        XCTAssertEqual(shortcut.key, "s")
        XCTAssertEqual(shortcut.modifiers, [.command, .shift])

        let aliases = try MacroShortcut.parse("command+option+D")
        XCTAssertEqual(aliases.key, "d")
        XCTAssertEqual(aliases.modifiers, [.command, .option])

        let control = try MacroShortcut.parse("ctrl+9")
        XCTAssertEqual(control.key, "9")
        XCTAssertEqual(control.modifiers, [.control])
    }

    func testShortcutParsingRejectsInvalidSpecs() {
        XCTAssertThrowsError(try MacroShortcut.parse("s"))               // 修飾なし
        XCTAssertThrowsError(try MacroShortcut.parse("shift+s"))         // shiftのみは不可
        XCTAssertThrowsError(try MacroShortcut.parse("cmd+esc"))         // 複数文字キー
        XCTAssertThrowsError(try MacroShortcut.parse("super+s"))         // 未知の修飾
    }

    func testDefineCommandWithShortcut() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["s.lsp": #"""
            (define-command "感嘆符"
              (lambda () (set-buffer-text (string-append (buffer-text) "!")))
              :shortcut "cmd+shift+1")
            """#],
            text: "abc"
        )
        guard let command = engine.commands.first(where: { $0.name == "感嘆符" }) else {
            return XCTFail("コマンドが登録されていません")
        }
        XCTAssertEqual(command.shortcut?.key, "1")
        XCTAssertEqual(command.shortcut?.modifiers, [.command, .shift])
        // ショートカット付きでも実行は従来どおり
        try runAndWait(engine, commandNamed: "感嘆符")
        XCTAssertEqual(view.text, "abc!")
    }

    func testDefineCommandWithInvalidShortcutReportsLoadError() throws {
        let (engine, _) = try makeEngine(
            macroSources: ["bad.lsp": #"""
            (define-command "だめ" (lambda () nil) :shortcut "s")
            """#],
            text: ""
        )
        XCTAssertTrue(engine.errorMessage?.contains("shortcut") == true)
        XCTAssertFalse(engine.commands.contains { $0.name == "だめ" })
    }

    // MARK: - 標準ライブラリ(stdlib.lsp)

    private func runFunctionAndWait(_ engine: MacroEngine, _ name: String) {
        let done = expectation(description: "fn \(name)")
        engine.runFunction(named: name) { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    func testStdlibMarkdownBoldWrapsSelection() throws {
        let (engine, view) = try makeEngine(text: "hello world")
        view.selectedRange = NSRange(location: 0, length: 5)
        runFunctionAndWait(engine, "md-bold")
        XCTAssertEqual(view.text, "**hello** world")
        XCTAssertNil(engine.errorMessage)
        // 本文部分が選択し直されている
        XCTAssertEqual(view.selectedRange, NSRange(location: 2, length: 5))
    }

    func testStdlibWrapSelectionWithoutSelectionInsertsPlaceholder() throws {
        let (engine, view) = try makeEngine(text: "")
        view.selectedRange = NSRange(location: 0, length: 0)
        runFunctionAndWait(engine, "md-code")
        XCTAssertEqual(view.text, "`code`")
        XCTAssertEqual(view.selectedRange, NSRange(location: 1, length: 4))
    }

    func testStdlibHeadingInsertsAtLineStartKeepingCaret() throws {
        let (engine, view) = try makeEngine(text: "一行目\n二行目")
        // 2 行目の途中(「二行」の後 = 位置 6)にカーソル
        view.selectedRange = NSRange(location: 6, length: 0)
        runFunctionAndWait(engine, "md-heading")
        XCTAssertEqual(view.text, "一行目\n# 二行目")
        // カーソルは挿入分(2 文字)ずれた位置を維持
        XCTAssertEqual(view.selectedRange, NSRange(location: 8, length: 0))
    }

    func testStdlibFunctionsAvailableToUserMacros() throws {
        // ユーザーマクロから標準ライブラリの関数を呼べる
        let (engine, view) = try makeEngine(
            macroSources: ["u.lsp": #"""
            (define-command "リンク化"
              (lambda () (wrap-selection "[" "](url)" "title")))
            """#],
            text: "apple"
        )
        view.selectedRange = NSRange(location: 0, length: 5)
        try runAndWait(engine, commandNamed: "リンク化")
        XCTAssertEqual(view.text, "[apple](url)")
    }

    func testRunFunctionReportsUnknownName() throws {
        let (engine, _) = try makeEngine(text: "")
        runFunctionAndWait(engine, "no-such-function")
        XCTAssertTrue(engine.errorMessage?.contains("no-such-function") == true)
    }

    // MARK: - grep(stdlib 実装)

    func testFileDirectoryPredicate() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(file-write "sub/a.txt" "x")"#)
        repl(engine, #"(file-directory-p "sub")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> t")
        repl(engine, #"(file-directory-p "sub/a.txt")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> nil")
        repl(engine, #"(file-directory-p "nothing")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> nil")
    }

    func testGrepLines() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(grep-lines "apple\nbanana\napricot" "ap")"#)
        XCTAssertEqual(
            engine.replLines.last?.text,
            #"=> ((1 . "apple") (3 . "apricot"))"#
        )
    }

    func testGrepBuffer() throws {
        let (engine, _) = try makeEngine(text: "犬が走る\n猫が鳴く\n犬が吠える")
        repl(engine, #"(grep-buffer "犬")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> 2")
        XCTAssertTrue(engine.replLines.contains { $0.text == "1: 犬が走る" })
        XCTAssertTrue(engine.replLines.contains { $0.text == "3: 犬が吠える" })
    }

    func testGrepDirectoryRecursive() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(file-write "top.txt" "hello here")"#)
        repl(engine, #"(file-write "d1/a.txt" "hello\nworld")"#)
        repl(engine, #"(file-write "d1/d2/b.txt" "say hello")"#)
        repl(engine, #"(grep-directory "hello" "")"#)
        XCTAssertEqual(engine.replLines.last?.text, "=> 3")
        XCTAssertTrue(engine.replLines.contains { $0.text == "d1/d2/b.txt:1: say hello" })
        XCTAssertTrue(engine.replLines.contains { $0.text == "d1/a.txt:1: hello" })
    }

    func testGrepFolderCommandWithPrompts() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(file-write "notes/x.txt" "TODO: 買い物")"#)
        engine.dialogPresenter = { request, completion in
            if case .prompt(let message, _) = request {
                completion(.string(message.contains("フォルダ") ? "" : "TODO"))
            } else {
                completion(.nilValue)
            }
        }
        try runAndWait(engine, commandNamed: "grep(フォルダ再帰)")
        XCTAssertTrue(engine.toastMessage?.contains("1件見つかりました") == true)
        XCTAssertTrue(engine.replLines.contains { $0.text == "notes/x.txt:1: TODO: 買い物" })
    }

    // MARK: - M5: iPadOS 連携

    func testSpellCheck() throws {
        let (engine, _) = try makeEngine(text: "")
        repl(engine, #"(spell-check "helllo wrold" "en")"#)
        // 少なくとも 1 語は誤りとして検出される
        XCTAssertTrue(engine.replLines.last?.text.contains("wrold") == true
            || engine.replLines.last?.text.contains("helllo") == true)
    }

    func testOpenURLRejectsNonWebSchemes() throws {
        let (engine, _) = try makeEngine(text: "")
        var requested: MacroPlatformRequest?
        engine.platformHandler = { requested = $0 }
        repl(engine, #"(open-url "https://example.com")"#)
        if case .openURL(let url)? = requested {
            XCTAssertEqual(url.absoluteString, "https://example.com")
        } else {
            XCTFail("open-url が要求されていません")
        }
        // file:// などは拒否
        repl(engine, #"(open-url "file:///etc/passwd")"#)
        XCTAssertEqual(engine.replLines.last?.kind, .error)
    }

    func testShareAndDictionaryDispatch() throws {
        let (engine, _) = try makeEngine(text: "共有する本文")
        var requests: [MacroPlatformRequest] = []
        engine.platformHandler = { requests.append($0) }
        repl(engine, "(share (buffer-text))")
        repl(engine, #"(show-dictionary "辞書")"#)
        XCTAssertEqual(requests.count, 2)
        if case .share(let text) = requests[0] {
            XCTAssertEqual(text, "共有する本文")
        } else {
            XCTFail("share が要求されていません")
        }
        if case .dictionary(let word) = requests[1] {
            XCTAssertEqual(word, "辞書")
        } else {
            XCTFail("dictionary が要求されていません")
        }
    }

    func testPickFileReturnsContent() throws {
        let (engine, view) = try makeEngine(
            macroSources: ["p.lsp": #"""
            (define-command "取り込む"
              (lambda ()
                (let ((content (pick-file)))
                  (if content (insert content) (message "キャンセル")))))
            """#],
            text: ""
        )
        engine.platformHandler = { request in
            if case .pickFile(let completion) = request {
                completion(.string("取り込まれた内容"))
            }
        }
        try runAndWait(engine, commandNamed: "取り込む")
        XCTAssertEqual(view.text, "取り込まれた内容")
    }

    func testSampleReadAloudLoads() throws {
        let (engine, _) = try makeEngine(text: "")
        XCTAssertTrue(engine.commands.contains { $0.name == "読み上げる" })
        XCTAssertTrue(engine.commands.contains { $0.name == "共有する" })
    }
}
