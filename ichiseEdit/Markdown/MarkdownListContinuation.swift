import Foundation

/// リスト・引用の自動継続。改行時に現在行の行頭マーカーを判定し、
/// 次の行へマーカーを引き継ぐ(空の項目なら終了してマーカーを消す)。
enum MarkdownListContinuation {

    enum Action: Equatable {
        /// 通常の改行(何もしない)
        case none
        /// 改行に続けて文字列を挿入する(例: "\n- ")
        case continueList(insert: String)
        /// 空の項目: 行頭からのマーカー長ぶんを削除する
        case terminateList(markerLength: Int)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d+)\.|(>))([ \t]+)(.*)$"#
    )

    /// - Parameter line: 改行を含まない 1 行分の文字列
    static func action(forLine line: String) -> Action {
        let ns = line as NSString
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return .none
        }

        let indent = ns.substring(with: match.range(at: 1))
        let spacing = ns.substring(with: match.range(at: 5))
        let content = ns.substring(with: match.range(at: 6))
        let markerLength = ns.length - (content as NSString).length

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return .terminateList(markerLength: markerLength)
        }

        if match.range(at: 2).location != NSNotFound {
            let bullet = ns.substring(with: match.range(at: 2))
            return .continueList(insert: "\n" + indent + bullet + spacing)
        }
        if match.range(at: 3).location != NSNotFound {
            let number = Int(ns.substring(with: match.range(at: 3))) ?? 0
            return .continueList(insert: "\n" + indent + "\(number + 1)." + spacing)
        }
        if match.range(at: 4).location != NSNotFound {
            return .continueList(insert: "\n" + indent + ">" + spacing)
        }
        return .none
    }
}
