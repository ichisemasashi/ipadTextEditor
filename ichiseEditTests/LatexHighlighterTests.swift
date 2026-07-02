import XCTest
@testable import ichiseEdit

final class LatexHighlighterTests: XCTestCase {

    private let latex = LanguageRegistry.language(forExtension: "tex")!

    private func tokens(_ text: String) -> [CodeHighlighter.Token] {
        CodeHighlighter.tokens(in: text, language: latex)
            .sorted { $0.range.location < $1.range.location }
    }

    private func kinds(_ text: String) -> [CodeHighlighter.Kind] {
        tokens(text).map(\.kind)
    }

    func testCommands() {
        let result = tokens(#"\documentclass{article}"#)
        XCTAssertEqual(result.map(\.kind), [.keyword])
        XCTAssertEqual(result[0].range, NSRange(location: 0, length: 14))
    }

    func testStarredCommand() {
        let result = tokens(#"\section*{はじめに}"#)
        XCTAssertEqual(result[0].range.length, 9) // \section* まで含む
    }

    func testComment() {
        XCTAssertEqual(kinds("本文 % コメント\n"), [.comment])
    }

    func testEscapedPercentIsNotComment() {
        // \% はコメント開始にならない(制御記号としてコマンド着色される)
        let result = tokens(#"50\% 引き % 本物のコメント"#)
        XCTAssertEqual(result.map(\.kind), [.keyword, .comment])
        XCTAssertEqual(result[0].range, NSRange(location: 2, length: 2)) // \%
    }

    func testInlineMathIsHighlighted() {
        XCTAssertEqual(kinds(#"式 $a + b = c$ を考える"#), [.string])
    }

    func testEscapedDollarDoesNotOpenMath() {
        XCTAssertTrue(tokens(#"価格は\$100です"#).allSatisfy { $0.kind == .keyword })
    }

    func testNumbersAreNotHighlighted() {
        XCTAssertTrue(tokens("1995年に発表された論文").isEmpty)
    }

    func testCommandInsideCommentIsNotKeyword() {
        XCTAssertEqual(kinds(#"% \textbf{comment}"#), [.comment])
    }

    func testBeginEndEnvironment() {
        let result = tokens("\\begin{itemize}\n\\item 項目\n\\end{itemize}\n")
        XCTAssertEqual(result.map(\.kind), [.keyword, .keyword, .keyword])
    }
}
