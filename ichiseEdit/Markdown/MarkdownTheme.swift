import UIKit

/// ハイライトの見た目の定義。フォントサイズに追従する。
struct MarkdownTheme {
    let fontSize: CGFloat

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
        ]
    }

    func attributes(for kind: MarkdownHighlighter.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading:
            return [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.systemBlue,
            ]
        case .listMarker:
            return [.foregroundColor: UIColor.systemBlue]
        case .blockquote:
            return [.foregroundColor: UIColor.secondaryLabel]
        case .codeBlock:
            return [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                .foregroundColor: UIColor.label,
                .backgroundColor: UIColor.secondarySystemFill.withAlphaComponent(0.35),
            ]
        case .codeSpan:
            return [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                .backgroundColor: UIColor.secondarySystemFill.withAlphaComponent(0.5),
            ]
        case .bold:
            return [.font: UIFont.systemFont(ofSize: fontSize, weight: .bold)]
        case .italic:
            let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor
                .withSymbolicTraits(.traitItalic)
            let font = descriptor.map { UIFont(descriptor: $0, size: fontSize) }
                ?? UIFont.italicSystemFont(ofSize: fontSize)
            return [.font: font]
        case .linkText:
            return [.foregroundColor: UIColor.systemBlue]
        case .linkURL:
            return [.foregroundColor: UIColor.secondaryLabel]
        }
    }
}
