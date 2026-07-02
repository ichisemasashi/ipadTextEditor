import UIKit

/// コードモード用の行番号ガター。UITextView のサブビューとして重ね、
/// スクロールに合わせて位置を追従させる。表示中のレイアウトフラグメント
/// (TextKit 2)だけを描画するため、大きなファイルでも軽い。
final class LineNumberGutterView: UIView {
    static let gutterWidth: CGFloat = 44

    weak var textView: UITextView?

    /// 各論理行の先頭 UTF-16 オフセット(昇順)
    private var lineStarts: [Int] = [0]

    var fontSize: CGFloat = 17 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuildLineStarts(text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 {
                starts.append(offset)
            }
        }
        lineStarts = starts
        setNeedsDisplay()
    }

    /// テキストビューの表示位置に合わせてガターを再配置する(スクロールごとに呼ぶ)
    func synchronize() {
        guard let textView else { return }
        frame = CGRect(
            x: 0,
            y: textView.contentOffset.y,
            width: Self.gutterWidth,
            height: textView.bounds.height
        )
        setNeedsDisplay()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        // 右端の区切り線
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(UIColor.separator.cgColor)
            context.fill(CGRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height))
        }

        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.7, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: UIColor.secondaryLabel,
        ]

        let viewport = layoutManager.textViewportLayoutController.viewportRange
            ?? layoutManager.documentRange
        let topInset = textView.textContainerInset.top
        let visibleMaxY = textView.contentOffset.y + textView.bounds.height

        layoutManager.enumerateTextLayoutFragments(
            from: viewport.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frameInContainer = fragment.layoutFragmentFrame
            let yInContent = frameInContainer.minY + topInset
            if yInContent > visibleMaxY { return false }

            let offset = contentManager.offset(
                from: layoutManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            let lineNumber = self.lineNumber(forUTF16Offset: offset)
            let text = "\(lineNumber)" as NSString
            let size = text.size(withAttributes: attributes)
            let drawPoint = CGPoint(
                x: self.bounds.width - size.width - 8,
                y: yInContent - textView.contentOffset.y + 2
            )
            text.draw(at: drawPoint, withAttributes: attributes)
            return true
        }
    }

    private func lineNumber(forUTF16Offset offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }
}
