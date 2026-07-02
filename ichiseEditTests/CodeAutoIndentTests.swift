import XCTest
@testable import ichiseEdit

final class CodeAutoIndentTests: XCTestCase {

    func testKeepsCurrentIndent() {
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "    let x = 1", indentUnit: "    ", indentsAfterColon: false),
            "\n    "
        )
    }

    func testIncreasesIndentAfterOpenBrace() {
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "func hello() {", indentUnit: "    ", indentsAfterColon: false),
            "\n    "
        )
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "    if ok {", indentUnit: "  ", indentsAfterColon: false),
            "\n      "
        )
    }

    func testIncreasesIndentAfterColonWhenEnabled() {
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "def main():", indentUnit: "    ", indentsAfterColon: true),
            "\n    "
        )
        // Swift などでは ":" で深くしない
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "case .a:", indentUnit: "    ", indentsAfterColon: false),
            "\n"
        )
    }

    func testTabIndentIsPreserved() {
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "\tfor i in range(3):", indentUnit: "\t", indentsAfterColon: true),
            "\n\t\t"
        )
    }

    func testPlainLine() {
        XCTAssertEqual(
            CodeAutoIndent.insertion(forLine: "print(x)", indentUnit: "    ", indentsAfterColon: true),
            "\n"
        )
    }
}
