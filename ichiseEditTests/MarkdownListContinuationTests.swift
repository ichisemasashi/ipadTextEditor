import XCTest
@testable import ichiseEdit

final class MarkdownListContinuationTests: XCTestCase {

    func testBulletContinues() {
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "- 項目"),
            .continueList(insert: "\n- ")
        )
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "* item"),
            .continueList(insert: "\n* ")
        )
    }

    func testNumberedListIncrements() {
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "3. 三番目"),
            .continueList(insert: "\n4. ")
        )
    }

    func testBlockquoteContinues() {
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "> 引用文"),
            .continueList(insert: "\n> ")
        )
    }

    func testIndentIsPreserved() {
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "  - ネスト"),
            .continueList(insert: "\n  - ")
        )
    }

    func testEmptyItemTerminates() {
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "- "),
            .terminateList(markerLength: 2)
        )
        XCTAssertEqual(
            MarkdownListContinuation.action(forLine: "  10. "),
            .terminateList(markerLength: 6)
        )
    }

    func testPlainLineDoesNothing() {
        XCTAssertEqual(MarkdownListContinuation.action(forLine: "ただの文章"), .none)
        XCTAssertEqual(MarkdownListContinuation.action(forLine: ""), .none)
        XCTAssertEqual(MarkdownListContinuation.action(forLine: "-ハイフンだが空白なし"), .none)
    }
}
