import XCTest
@testable import ichiseEdit

final class CodeHighlighterTests: XCTestCase {

    private let swift = LanguageRegistry.language(forExtension: "swift")!
    private let python = LanguageRegistry.language(forExtension: "py")!
    private let sql = LanguageRegistry.language(forExtension: "sql")!

    private func kinds(_ text: String, _ language: LanguageDefinition) -> [CodeHighlighter.Kind] {
        CodeHighlighter.tokens(in: text, language: language)
            .sorted { $0.range.location < $1.range.location }
            .map(\.kind)
    }

    func testKeywordAndNumber() {
        XCTAssertEqual(kinds("let x = 42", swift), [.keyword, .number])
    }

    func testLineComment() {
        let tokens = CodeHighlighter.tokens(in: "let a = 1 // let b = 2\n", language: swift)
            .sorted { $0.range.location < $1.range.location }
        // コメント内の let / 2 はキーワード・数値として扱わない
        XCTAssertEqual(tokens.map(\.kind), [.keyword, .number, .comment])
    }

    func testBlockComment() {
        XCTAssertEqual(kinds("/* let if */ var x", swift), [.comment, .keyword])
    }

    func testStringSuppressesKeywords() {
        XCTAssertEqual(kinds(#"print("let if 42")"#, swift), [.string])
    }

    func testCommentMarkerInsideString() {
        // 文字列中の // はコメントにならない
        XCTAssertEqual(kinds(#"let url = "https://example.com""#, swift), [.keyword, .string])
    }

    func testEscapedQuoteStaysInString() {
        XCTAssertEqual(kinds(#"let s = "a\"b" + name"#, swift), [.keyword, .string])
    }

    func testUnterminatedStringStopsAtLineEnd() {
        let tokens = CodeHighlighter.tokens(in: "s = \"abc\nx = 1\n", language: python)
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertEqual(stringToken?.range, NSRange(location: 4, length: 4))
        XCTAssertTrue(tokens.contains { $0.kind == .number })
    }

    func testPythonTripleQuotedString() {
        let text = "s = \"\"\"first\nif True:\n\"\"\"\nx = 1\n"
        let tokens = CodeHighlighter.tokens(in: text, language: python)
        // 三重クォート内の if はキーワードにしない
        XCTAssertFalse(tokens.contains { $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.kind == .string })
    }

    func testSQLKeywordsAreCaseInsensitive() {
        XCTAssertEqual(kinds("SELECT id FROM users", sql), [.keyword, .keyword])
    }

    func testJapaneseTextIsUntouched() {
        XCTAssertTrue(CodeHighlighter.tokens(in: "これはコードではない文章です。", language: swift).isEmpty)
    }
}
