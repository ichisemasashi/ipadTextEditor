import UIKit

/// コードハイライトの見た目。等幅フォントを基本とする。
struct CodeTheme {
    let fontSize: CGFloat

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: UIColor.label,
        ]
    }

    func attributes(for kind: CodeHighlighter.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .comment:
            return [.foregroundColor: UIColor.systemGray]
        case .string:
            return [.foregroundColor: UIColor.systemRed]
        case .keyword:
            return [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.systemPurple,
            ]
        case .number:
            return [.foregroundColor: UIColor.systemOrange]
        }
    }
}
