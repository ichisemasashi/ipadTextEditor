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

    private func temporaryDirectory(create: Bool) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroEngineTests-\(UUID().uuidString)")
        if create {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func makeEngine(directory: URL, text: String) -> (MacroEngine, UITextView) {
        let engine = MacroEngine(directory: directory)
        let proxy = TextViewProxy()
        let view = UITextView(usingTextLayoutManager: true)
        view.text = text
        proxy.textView = view
        engine.proxy = proxy
        engine.loadIfNeeded()
        return (engine, view)
    }

    func testLoadAndRunCommand() throws {
        let dir = temporaryDirectory(create: true)
        try #"""
        (define-command "びっくり"
          (lambda () (set-buffer-text (string-append (buffer-text) "!"))))
        """#.write(to: dir.appendingPathComponent("a.lsp"), atomically: true, encoding: .utf8)

        let (engine, view) = makeEngine(directory: dir, text: "abc")
        XCTAssertEqual(engine.commands.map(\.name), ["びっくり"])
        engine.run(engine.commands[0])
        XCTAssertEqual(view.text, "abc!")
        XCTAssertNil(engine.errorMessage)
    }

    func testSamplesInstalledWhenDirectoryMissing() {
        let dir = temporaryDirectory(create: false)
        let (engine, _) = makeEngine(directory: dir, text: "")
        XCTAssertEqual(engine.commands.count, MacroEngine.sampleMacros.count)
    }

    func testSampleSortLines() {
        let dir = temporaryDirectory(create: false)
        let (engine, view) = makeEngine(directory: dir, text: "banana\napple\ncherry")
        guard let sortCommand = engine.commands.first(where: { $0.name == "行をソート" }) else {
            return XCTFail("サンプルコマンドがありません")
        }
        engine.run(sortCommand)
        XCTAssertEqual(view.text, "apple\nbanana\ncherry")
        XCTAssertNil(engine.errorMessage)
    }

    func testSampleDedupeLines() {
        let dir = temporaryDirectory(create: false)
        let (engine, view) = makeEngine(directory: dir, text: "a\nb\na\nc\nb")
        guard let command = engine.commands.first(where: { $0.name == "重複行を削除" }) else {
            return XCTFail("サンプルコマンドがありません")
        }
        engine.run(command)
        XCTAssertEqual(view.text, "a\nb\nc")
        XCTAssertNil(engine.errorMessage)
    }

    func testLoadErrorIsReported() throws {
        let dir = temporaryDirectory(create: true)
        try "(defun broken".write(
            to: dir.appendingPathComponent("bad.lsp"), atomically: true, encoding: .utf8
        )
        let (engine, _) = makeEngine(directory: dir, text: "")
        XCTAssertNotNil(engine.errorMessage)
    }

    func testRuntimeErrorIsReportedAndDoesNotCrash() throws {
        let dir = temporaryDirectory(create: true)
        try #"(define-command "失敗" (lambda () (error "わざと")))"#.write(
            to: dir.appendingPathComponent("f.lsp"), atomically: true, encoding: .utf8
        )
        let (engine, view) = makeEngine(directory: dir, text: "keep")
        engine.run(engine.commands[0])
        XCTAssertEqual(view.text, "keep")
        XCTAssertTrue(engine.errorMessage?.contains("わざと") == true)
    }
}
