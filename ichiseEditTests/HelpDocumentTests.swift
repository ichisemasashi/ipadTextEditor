import XCTest
@testable import ichiseEdit

final class HelpDocumentTests: XCTestCase {

    private func blocks(_ md: String) -> [HelpDocument.Block] {
        HelpDocument.parse(md)
    }

    func testHeadingAndParagraph() {
        let result = blocks("# 見出し\n\n本文です。")
        XCTAssertEqual(result.count, 2)
        if case .heading(let level, let text) = result[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(String(text.characters), "見出し")
        } else { XCTFail("見出しが解析されていません") }
        if case .paragraph(let text) = result[1] {
            XCTAssertEqual(String(text.characters), "本文です。")
        } else { XCTFail("段落が解析されていません") }
    }

    func testHeadingLevels() {
        if case .heading(let level, _) = blocks("### 三段階")[0] {
            XCTAssertEqual(level, 3)
        } else { XCTFail() }
        // # のあとに空白がないものは見出しにしない
        if case .paragraph = blocks("#タグ")[0] {} else { XCTFail("見出し扱いされています") }
    }

    func testCodeBlock() {
        let result = blocks("```\n(+ 1 2)\n(* 3 4)\n```")
        XCTAssertEqual(result.count, 1)
        if case .codeBlock(let code) = result[0] {
            XCTAssertEqual(code, "(+ 1 2)\n(* 3 4)")
        } else { XCTFail("コードブロックが解析されていません") }
    }

    func testList() {
        let result = blocks("- 項目1\n- 項目2\n1. 番号")
        XCTAssertEqual(result.count, 3)
        if case .listItem(let marker, let text) = result[0] {
            XCTAssertEqual(marker, "•")
            XCTAssertEqual(String(text.characters), "項目1")
        } else { XCTFail() }
        if case .listItem(let marker, _) = result[2] {
            XCTAssertEqual(marker, "1.")
        } else { XCTFail() }
    }

    func testTable() {
        let md = """
        | 関数 | 説明 |
        |---|---|
        | `insert` | 挿入する |
        | `delete` | 削除する |
        """
        let result = blocks(md)
        XCTAssertEqual(result.count, 1)
        if case .table(let headers, let rows) = result[0] {
            XCTAssertEqual(headers.map { String($0.characters) }, ["関数", "説明"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(String(rows[0][1].characters), "挿入する")
            // インライン装飾(`insert`)は AttributedString 側で処理され、素の文字が残る
            XCTAssertEqual(String(rows[1][0].characters), "delete")
        } else { XCTFail("表が解析されていません") }
    }

    func testDivider() {
        let result = blocks("上\n\n---\n\n下")
        XCTAssertEqual(result.count, 3)
        if case .divider = result[1] {} else { XCTFail("区切り線が解析されていません") }
    }

    func testParagraphMerging() {
        // 連続する行は 1 段落にまとまる
        let result = blocks("一行目\n二行目\n三行目")
        XCTAssertEqual(result.count, 1)
        if case .paragraph(let text) = result[0] {
            XCTAssertEqual(String(text.characters), "一行目 二行目 三行目")
        } else { XCTFail() }
    }

    /// バンドルされたマニュアルが実際に読み込めて、相応のブロック数になること
    func testBundledManualLoads() {
        let doc = ManualView.loadBundledManual()
        XCTAssertGreaterThan(doc.blocks.count, 50, "マニュアルのブロック数が少なすぎます(バンドル漏れ?)")
        // 見出し・表・コードブロックが最低 1 つずつある
        XCTAssertTrue(doc.blocks.contains { if case .heading = $0.block { return true }; return false })
        XCTAssertTrue(doc.blocks.contains { if case .table = $0.block { return true }; return false })
        XCTAssertTrue(doc.blocks.contains { if case .codeBlock = $0.block { return true }; return false })
    }
}
