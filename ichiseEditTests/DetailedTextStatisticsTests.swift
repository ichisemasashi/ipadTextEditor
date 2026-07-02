import XCTest
@testable import ichiseEdit

final class DetailedTextStatisticsTests: XCTestCase {

    func testEmpty() {
        let stats = DetailedTextStatistics(counting: "")
        XCTAssertEqual(stats.characters, 0)
        XCTAssertEqual(stats.charactersExcludingWhitespace, 0)
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.lines, 1)
        XCTAssertEqual(stats.paragraphs, 0)
        XCTAssertEqual(stats.manuscriptPages, 0)
    }

    func testJapaneseParagraphs() {
        // 空行区切りで 2 段落
        let stats = DetailedTextStatistics(counting: "こんにちは 世界\n\n2段落目です。\n")
        XCTAssertEqual(stats.characters, 18)
        XCTAssertEqual(stats.charactersExcludingWhitespace, 14)
        XCTAssertEqual(stats.lines, 4)
        XCTAssertEqual(stats.paragraphs, 2)
    }

    func testConsecutiveLinesAreOneParagraph() {
        // 空行を挟まない連続行は 1 段落と数える
        let stats = DetailedTextStatistics(counting: "1行目\n2行目\n3行目")
        XCTAssertEqual(stats.paragraphs, 1)
        XCTAssertEqual(stats.lines, 3)
    }

    func testEnglishWordCount() {
        let stats = DetailedTextStatistics(counting: "Hello world, this is a test.")
        XCTAssertEqual(stats.words, 6)
    }

    func testManuscriptPages() {
        // 800 文字ちょうど → 2.0 枚
        XCTAssertEqual(
            DetailedTextStatistics(counting: String(repeating: "あ", count: 800)).manuscriptPages,
            2.0
        )
        // 801 文字 → 0.1 枚単位で切り上げて 2.1 枚
        XCTAssertEqual(
            DetailedTextStatistics(counting: String(repeating: "あ", count: 801)).manuscriptPages,
            2.1,
            accuracy: 0.001
        )
        // 空白・改行は原稿用紙換算に含めない
        XCTAssertEqual(
            DetailedTextStatistics(counting: String(repeating: "あ ", count: 400)).manuscriptPages,
            1.0
        )
    }
}
