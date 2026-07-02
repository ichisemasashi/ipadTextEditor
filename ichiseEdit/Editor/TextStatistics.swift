import Foundation

/// ステータスバーに表示する文字数・行数。
struct TextStatistics: Equatable, Sendable {
    var characters = 0
    var lines = 1

    init() {}

    /// 1 回の走査で文字数と行数を数える。
    init(counting text: String) {
        var characters = 0
        var lines = 1
        for character in text {
            characters += 1
            if character == "\n" { lines += 1 }
        }
        self.characters = characters
        self.lines = lines
    }
}
