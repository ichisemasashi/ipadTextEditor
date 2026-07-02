import Foundation

/// 統計ポップオーバーに表示する詳細な文字数情報。
/// 全文走査を伴うため、表示時にバックグラウンドで計算する。
struct DetailedTextStatistics: Equatable, Sendable {
    var characters = 0
    var charactersExcludingWhitespace = 0
    var words = 0
    var lines = 1
    var paragraphs = 0

    /// 400 字詰め原稿用紙の換算枚数(空白・改行を除いた文字数で計算、0.1 枚単位で切り上げ)
    var manuscriptPages: Double {
        guard charactersExcludingWhitespace > 0 else { return 0 }
        return (Double(charactersExcludingWhitespace) / 400 * 10).rounded(.up) / 10
    }

    init() {}

    init(counting text: String) {
        var lineHasContent = false
        var inParagraph = false

        for character in text {
            characters += 1
            if character == "\n" {
                lines += 1
                if !lineHasContent {
                    inParagraph = false
                }
                lineHasContent = false
                continue
            }
            if !character.isWhitespace {
                charactersExcludingWhitespace += 1
                lineHasContent = true
                if !inParagraph {
                    paragraphs += 1
                    inParagraph = true
                }
            }
        }

        var wordCount = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            wordCount += 1
        }
        words = wordCount
    }
}
