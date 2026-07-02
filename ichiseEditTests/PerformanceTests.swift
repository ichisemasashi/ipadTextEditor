import XCTest
@testable import ichiseEdit

/// 要件定義 §5「1MB 程度のテキストでもスクロール・入力にもたつきがないこと」の検証。
final class PerformanceTests: XCTestCase {

    /// 約 1MB(UTF-8)の日英混在テキスト
    static let oneMegabyteText: String = {
        let line = "吾輩は猫である。名前はまだ無い。The quick brown fox jumps over the lazy dog. 0123456789\n"
        var text = ""
        text.reserveCapacity(1_200_000)
        while text.utf8.count < 1_000_000 {
            text += line
        }
        return text
    }()

    // MARK: - ドキュメント読み書き(ファイルを開く/保存する経路)

    func testDecodeUTF8_1MB() {
        let data = Data(Self.oneMegabyteText.utf8)
        measure {
            _ = String(data: data, encoding: .utf8)
        }
    }

    func testEncodeUTF8_1MB() {
        let text = Self.oneMegabyteText
        measure {
            _ = Data(text.utf8)
        }
    }

    // MARK: - 文字数・行数カウント(ステータス表示の経路)

    func testCharacterAndLineCount_1MB() {
        let text = Self.oneMegabyteText
        measure {
            let statistics = TextStatistics(counting: text)
            XCTAssertGreaterThan(statistics.characters, 0)
            XCTAssertGreaterThan(statistics.lines, 1)
        }
    }

    /// 毎キーストロークで発生する 1MB 文字列の等値比較(updateUIView の差分チェック相当)
    func testStringComparison_1MB() {
        let a = Self.oneMegabyteText
        let b = Self.oneMegabyteText + "x"
        measure {
            _ = (a != b)
        }
    }

    // MARK: - UITextView(TextKit 2)への流し込みと初期レイアウト

    @MainActor
    func testTextViewSetTextAndLayout_1MB() {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        measure {
            textView.text = Self.oneMegabyteText
            textView.layoutIfNeeded()
        }
    }
}
