import XCTest
@testable import ichiseEdit

final class MarkdownHighlighterTests: XCTestCase {

    private func kinds(in text: String) -> [MarkdownHighlighter.Kind] {
        MarkdownHighlighter.tokens(in: text).map(\.kind)
    }

    func testHeading() {
        let tokens = MarkdownHighlighter.tokens(in: "# 見出し\n本文\n")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .heading)
        XCTAssertEqual(tokens[0].range, NSRange(location: 0, length: 5))
    }

    func testHashWithoutSpaceIsNotHeading() {
        XCTAssertTrue(kinds(in: "#タグ\n").isEmpty)
    }

    func testBoldAndItalic() {
        XCTAssertEqual(kinds(in: "**強い**と*弱い*\n"), [.bold, .italic])
    }

    func testItalicDoesNotMatchInsideBold() {
        let tokens = MarkdownHighlighter.tokens(in: "**bold** normal\n")
        XCTAssertEqual(tokens.map(\.kind), [.bold])
    }

    func testCodeSpanSuppressesInlineStyles() {
        XCTAssertEqual(kinds(in: "`**not bold**`\n"), [.codeSpan])
    }

    func testCodeFence() {
        let text = "```\n**中身は装飾しない**\n```\n後続 **太字**\n"
        let tokens = MarkdownHighlighter.tokens(in: text)
        XCTAssertEqual(tokens.map(\.kind), [.codeBlock, .codeBlock, .codeBlock, .bold])
    }

    func testListMarkerAndBlockquote() {
        XCTAssertEqual(kinds(in: "- 項目\n"), [.listMarker])
        XCTAssertEqual(kinds(in: "12. 項目\n"), [.listMarker])
        XCTAssertEqual(kinds(in: "> 引用\n"), [.blockquote])
    }

    func testLink() {
        let tokens = MarkdownHighlighter.tokens(in: "[Apple](https://apple.com)\n")
        XCTAssertEqual(tokens.map(\.kind), [.linkText, .linkURL])
        XCTAssertEqual(tokens[0].range, NSRange(location: 1, length: 5))
    }

    func testRangesAreOffsetByLine() {
        let tokens = MarkdownHighlighter.tokens(in: "普通の行\n**太字**\n")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].range, NSRange(location: 5, length: 6))
    }
}
