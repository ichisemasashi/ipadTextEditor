import Foundation

/// コードの自動インデント。改行時に前行のインデントを引き継ぎ、
/// ブロック開始記号の直後では 1 段深くする。
enum CodeAutoIndent {

    /// - Parameters:
    ///   - line: カーソル位置より左側の行内容
    ///   - indentUnit: 1 段分のインデント文字列("    " や "\t")
    ///   - indentsAfterColon: 行末 ":" でも 1 段深くするか(Python など)
    /// - Returns: 改行として挿入する文字列
    static func insertion(forLine line: String, indentUnit: String, indentsAfterColon: Bool) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        var result = "\n" + leading

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last {
            if "{([".contains(last) || (indentsAfterColon && last == ":") {
                result += indentUnit
            }
        }
        return result
    }
}
