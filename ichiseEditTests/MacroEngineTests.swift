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
}
