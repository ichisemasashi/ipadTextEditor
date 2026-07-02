import XCTest
@testable import ichiseEdit

final class TextStatisticsTests: XCTestCase {

    func testEmptyText() {
        let statistics = TextStatistics(counting: "")
        XCTAssertEqual(statistics.characters, 0)
        XCTAssertEqual(statistics.lines, 1)
    }

    func testSingleLine() {
        let statistics = TextStatistics(counting: "あいうabc")
        XCTAssertEqual(statistics.characters, 6)
        XCTAssertEqual(statistics.lines, 1)
    }

    func testMultipleLines() {
        let statistics = TextStatistics(counting: "abc\nあいう\n")
        XCTAssertEqual(statistics.characters, 8)
        XCTAssertEqual(statistics.lines, 3)
    }

    func testEmojiCountsAsSingleCharacter() {
        let statistics = TextStatistics(counting: "👨‍👩‍👧‍👦🇯🇵")
        XCTAssertEqual(statistics.characters, 2)
        XCTAssertEqual(statistics.lines, 1)
    }
}
