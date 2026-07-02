import XCTest
@testable import ichiseEdit

final class LispHaskellHighlighterTests: XCTestCase {

    private func language(_ ext: String) -> LanguageDefinition {
        LanguageRegistry.language(forExtension: ext)!
    }

    private func kinds(_ text: String, _ ext: String) -> [CodeHighlighter.Kind] {
        CodeHighlighter.tokens(in: text, language: language(ext))
            .sorted { $0.range.location < $1.range.location }
            .map(\.kind)
    }

    // MARK: - Common Lisp

    func testCommonLispDefunAndComment() {
        XCTAssertEqual(
            kinds("; コメント\n(defun add (a b) a)", "lisp"),
            [.comment, .keyword]
        )
    }

    func testCommonLispBlockCommentAndCaseInsensitive() {
        XCTAssertEqual(kinds("#| let if |# (DEFUN f ())", "lisp"), [.comment, .keyword])
    }

    // MARK: - Scheme

    func testSchemeSymbolBoundaries() {
        // set! は完全一致でキーワード。foo-do-bar の中の do は誤検出しない
        XCTAssertEqual(kinds("(set! foo-do-bar 10)", "scm"), [.keyword, .number])
    }

    func testSchemePredicateKeywords() {
        XCTAssertEqual(kinds("(null? xs)", "scm"), [.keyword])
        XCTAssertEqual(kinds("(if #t 1 2)", "scm"), [.keyword, .keyword, .number, .number])
    }

    // MARK: - Clojure

    func testClojureThreadingMacro() {
        XCTAssertEqual(kinds("(->> xs (map inc))", "clj"), [.keyword, .keyword])
    }

    func testClojureDefnMinusIsNotDefn() {
        // defn- は defn とは別キーワードとして完全一致で判定される
        let tokens = CodeHighlighter.tokens(in: "(defn- helper [])", language: language("clj"))
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].range.length, 5)
    }

    // MARK: - ISLISP

    func testISLisp() {
        XCTAssertEqual(kinds("(defglobal *limit* 10)", "lsp"), [.keyword, .number])
    }

    // MARK: - Emacs Lisp

    func testEmacsLisp() {
        XCTAssertEqual(
            kinds("(setq fill-column 80) ; 設定", "el"),
            [.keyword, .number, .comment]
        )
    }

    // MARK: - Haskell

    func testHaskellCommentsAndKeywords() {
        XCTAssertEqual(
            kinds("-- コメント\nlet x = 42", "hs"),
            [.comment, .keyword, .number]
        )
        XCTAssertEqual(kinds("{- let if -} where", "hs"), [.comment, .keyword])
    }

    func testHaskellPrimeIdentifierIsNotKeyword() {
        // let' のような ' 付き識別子の中の let は誤検出しない
        XCTAssertEqual(kinds("foldl let' 0", "hs"), [.number])
    }
}
