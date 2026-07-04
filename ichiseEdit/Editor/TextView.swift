import SwiftUI
import UIKit

/// 折り返し OFF 時の横スクロールに対応した UITextView。
/// TextKit 2 はコンテンツ幅を自動計算しないため、外部で測った幅を
/// contentSize に強制する(UITextView 自身の再計算で上書きされないよう setter で守る)。
final class WrapAwareTextView: UITextView {
    var horizontalContentWidth: CGFloat = 0

    override var contentSize: CGSize {
        get { super.contentSize }
        set {
            var size = newValue
            if horizontalContentWidth > 0 {
                size.width = max(size.width, horizontalContentWidth)
            }
            super.contentSize = size
        }
    }
}

/// エディタ本体。TextKit 2 で動作する UITextView のラッパー。
/// 注意: `layoutManager` にアクセスすると TextKit 1 にフォールバックするため、
/// レイアウト操作は必ず `textLayoutManager` 経由で行うこと。
struct TextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var mode: EditorMode = .plainText
    var indentUsesSpaces: Bool = true
    var indentWidth: Int = 4
    var focusMode: Bool = false
    var wordWrap: Bool = true
    var selectionCount: Binding<Int>?
    var proxy: TextViewProxy?
    var macroEngine: MacroEngine?

    private var baseFont: UIFont {
        mode.codeLanguage != nil
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = WrapAwareTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.font = baseFont
        textView.isFindInteractionEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.text = text
        context.coordinator.observeKeyboard(for: textView)
        proxy?.textView = textView

        if mode.codeLanguage != nil {
            textView.textContainerInset.left = LineNumberGutterView.gutterWidth + 6
            let gutter = LineNumberGutterView(frame: .zero)
            gutter.textView = textView
            gutter.fontSize = fontSize
            gutter.rebuildLineStarts(text: text)
            textView.addSubview(gutter)
            context.coordinator.gutter = gutter
            DispatchQueue.main.async {
                gutter.synchronize()
            }
        }

        if !wordWrap {
            Self.applyWordWrap(false, to: textView)
            DispatchQueue.main.async {
                context.coordinator.updateHorizontalContentSize(textView)
            }
        }
        context.coordinator.applyHighlightIfNeeded(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let fontChanged = textView.font?.pointSize != CGFloat(fontSize)
        let focusChanged = context.coordinator.parent.focusMode != focusMode
        context.coordinator.parent = self

        if focusChanged {
            context.coordinator.refreshHighlight(textView)
        }
        // UITextView がレイアウト時にコンテナ設定を戻すことがあるため、
        // 変更検知ではなく実際のコンテナ状態と突き合わせて自己修復する
        let container = textView.textContainer
        let containerMismatched = wordWrap
            ? !container.widthTracksTextView
            : (container.widthTracksTextView
                || container.size.width < CGFloat.greatestFiniteMagnitude / 2)
        if containerMismatched {
            Self.applyWordWrap(wordWrap, to: textView)
            context.coordinator.updateHorizontalContentSize(textView)
            context.coordinator.gutter?.synchronize()
        }

        // 入力のたびに再設定するとカーソル位置が失われるため、差分がある時のみ反映する
        if textView.text != text {
            textView.text = text
            context.coordinator.applyHighlightIfNeeded(to: textView)
            context.coordinator.gutter?.rebuildLineStarts(text: text)
        }
        if fontChanged {
            textView.font = baseFont
            context.coordinator.gutter?.fontSize = fontSize
            context.coordinator.applyHighlightIfNeeded(to: textView)
        }
        context.coordinator.gutter?.synchronize()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 折り返し OFF ではテキストコンテナの幅を無制限にして横スクロールで表示する
    static func applyWordWrap(_ wrap: Bool, to textView: UITextView) {
        let container = textView.textContainer
        if wrap {
            container.widthTracksTextView = true
            container.size = CGSize(
                width: textView.bounds.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            container.widthTracksTextView = false
            container.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        var gutter: LineNumberGutterView?
        private var pendingHighlight: DispatchWorkItem?
        private(set) var lastFocusParagraph: NSRange?

        /// これを超える長さの文書ではハイライトを無効化する(入力性能を優先)
        private static let highlightLengthLimit = 200_000

        init(parent: TextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            scheduleDeferredLayoutWork(for: textView)
            gutter?.rebuildLineStarts(text: textView.text ?? "")
        }

        /// 折り返し OFF 時: 全行をレイアウトして実際の使用幅を測り、
        /// 横スクロールできるように contentSize の幅を確定する
        func updateHorizontalContentSize(_ textView: UITextView) {
            guard let wrapAware = textView as? WrapAwareTextView else { return }
            if parent.wordWrap {
                wrapAware.horizontalContentWidth = 0
                textView.contentSize.width = textView.bounds.width
                return
            }
            guard let layoutManager = textView.textLayoutManager,
                  (textView.text ?? "").utf16.count <= Self.highlightLengthLimit
            else { return }

            layoutManager.ensureLayout(for: layoutManager.documentRange)
            let usage = layoutManager.usageBoundsForTextContainer
            let width = ceil(usage.maxX)
                + textView.textContainerInset.left
                + textView.textContainerInset.right
                + 24
            wrapAware.horizontalContentWidth = max(width, textView.bounds.width)
            textView.contentSize.width = wrapAware.horizontalContentWidth
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // 選択範囲の文字数(グラフェム単位)をステータスバーへ通知する
            if let binding = parent.selectionCount {
                let selection = textView.selectedRange
                let count: Int
                if selection.length == 0 {
                    count = 0
                } else {
                    count = ((textView.text ?? "") as NSString)
                        .substring(with: selection).count
                }
                if binding.wrappedValue != count {
                    binding.wrappedValue = count
                }
            }
            // 集中モード: カーソルの段落が変わったら減光範囲を更新する
            if parent.focusMode, textView.markedTextRange == nil {
                let ns = (textView.text ?? "") as NSString
                let location = min(textView.selectedRange.location, ns.length)
                let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
                if paragraph != lastFocusParagraph {
                    highlight(textView)
                }
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gutter?.synchronize()
        }

        // MARK: - 選択範囲クイック適用(編集メニューへのマクロ追加)

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0,
                  let engine = parent.macroEngine,
                  !engine.selectionCommands.isEmpty else { return nil }
            let actions = engine.selectionCommands.map { command in
                UIAction(title: command.name) { [weak engine] _ in
                    engine?.runSelection(command)
                }
            }
            let macroMenu = UIMenu(
                title: String(localized: "Macros"),
                image: UIImage(systemName: "hammer"),
                children: actions
            )
            return UIMenu(children: suggestedActions + [macroMenu])
        }

        // MARK: - 改行・タブの編集支援

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            switch parent.mode {
            case .plainText:
                return true
            case .markdown:
                return handleMarkdownNewline(textView, range: range, replacement: replacement)
            case .code(let language):
                return handleCodeEditing(textView, range: range, replacement: replacement, language: language)
            }
        }

        private func handleMarkdownNewline(
            _ textView: UITextView,
            range: NSRange,
            replacement: String
        ) -> Bool {
            guard replacement == "\n", range.length == 0 else { return true }

            let ns = (textView.text ?? "") as NSString
            var lineStart = 0
            var contentsEnd = 0
            ns.getLineStart(
                &lineStart,
                end: nil,
                contentsEnd: &contentsEnd,
                for: NSRange(location: range.location, length: 0)
            )
            // 行末で改行した時だけ自動継続する(行の途中では通常の改行)
            guard range.location == contentsEnd else { return true }

            let line = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            switch MarkdownListContinuation.action(forLine: line) {
            case .none:
                return true
            case .continueList(let insert):
                textView.insertText(insert)
                return false
            case .terminateList(let markerLength):
                if let start = textView.position(from: textView.beginningOfDocument, offset: lineStart),
                   let end = textView.position(from: start, offset: markerLength),
                   let markerRange = textView.textRange(from: start, to: end) {
                    textView.replace(markerRange, withText: "")
                }
                return false
            }
        }

        private func handleCodeEditing(
            _ textView: UITextView,
            range: NSRange,
            replacement: String,
            language: LanguageDefinition
        ) -> Bool {
            // タブキー: スペース挿入設定ならタブ幅ぶんのスペースに置き換える
            if replacement == "\t", parent.indentUsesSpaces {
                textView.insertText(String(repeating: " ", count: parent.indentWidth))
                return false
            }
            // 改行: 前行のインデントを引き継ぐ
            if replacement == "\n", range.length == 0 {
                let ns = (textView.text ?? "") as NSString
                var lineStart = 0
                ns.getLineStart(&lineStart, end: nil, contentsEnd: nil, for: NSRange(location: range.location, length: 0))
                let lineBeforeCaret = ns.substring(
                    with: NSRange(location: lineStart, length: range.location - lineStart)
                )
                let indentUnit = parent.indentUsesSpaces
                    ? String(repeating: " ", count: parent.indentWidth)
                    : "\t"
                let insertion = CodeAutoIndent.insertion(
                    forLine: lineBeforeCaret,
                    indentUnit: indentUnit,
                    indentsAfterColon: language.indentsAfterColon
                )
                if insertion != "\n" {
                    textView.insertText(insertion)
                    return false
                }
            }
            return true
        }

        // MARK: - シンタックスハイライト

        func applyHighlightIfNeeded(to textView: UITextView) {
            guard parent.mode != .plainText || parent.focusMode else { return }
            highlight(textView)
        }

        /// 集中モードの切替時など、状態が変わった時に属性を丸ごと引き直す
        func refreshHighlight(_ textView: UITextView) {
            highlight(textView)
        }

        private func scheduleDeferredLayoutWork(for textView: UITextView) {
            let needsHighlight = parent.mode != .plainText || parent.focusMode
            guard needsHighlight || !parent.wordWrap else { return }
            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                if needsHighlight {
                    self.highlight(textView)
                }
                self.updateHorizontalContentSize(textView)
            }
            pendingHighlight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        private func highlight(_ textView: UITextView) {
            // 日本語入力の変換中に属性を触ると変換が壊れるため、確定を待つ
            guard textView.markedTextRange == nil else { return }
            let text = textView.text ?? ""
            guard text.utf16.count <= Self.highlightLengthLimit else { return }

            let baseAttributes: [NSAttributedString.Key: Any]
            var tokenAttributes: [(NSRange, [NSAttributedString.Key: Any])] = []

            switch parent.mode {
            case .plainText:
                baseAttributes = [
                    .font: UIFont.systemFont(ofSize: CGFloat(parent.fontSize)),
                    .foregroundColor: UIColor.label,
                ]
            case .markdown:
                let theme = MarkdownTheme(fontSize: CGFloat(parent.fontSize))
                baseAttributes = theme.baseAttributes
                for token in MarkdownHighlighter.tokens(in: text) {
                    tokenAttributes.append((token.range, theme.attributes(for: token.kind)))
                }
            case .code(let language):
                let theme = CodeTheme(fontSize: CGFloat(parent.fontSize))
                baseAttributes = theme.baseAttributes
                for token in CodeHighlighter.tokens(in: text, language: language) {
                    tokenAttributes.append((token.range, theme.attributes(for: token.kind)))
                }
            }

            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
            for (range, attributes) in tokenAttributes {
                storage.addAttributes(attributes, range: range)
            }
            // 集中モード: カーソルのある段落以外を減光する
            if parent.focusMode {
                let ns = text as NSString
                let location = min(textView.selectedRange.location, ns.length)
                let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
                lastFocusParagraph = paragraph
                let dimColor = UIColor.tertiaryLabel
                if paragraph.location > 0 {
                    storage.addAttribute(
                        .foregroundColor,
                        value: dimColor,
                        range: NSRange(location: 0, length: paragraph.location)
                    )
                }
                let paragraphEnd = NSMaxRange(paragraph)
                if paragraphEnd < storage.length {
                    storage.addAttribute(
                        .foregroundColor,
                        value: dimColor,
                        range: NSRange(location: paragraphEnd, length: storage.length - paragraphEnd)
                    )
                }
            } else {
                lastFocusParagraph = nil
            }
            storage.endEditing()
            textView.typingAttributes = baseAttributes
        }

        // MARK: - キーボードによる編集領域の遮蔽対策

        func observeKeyboard(for textView: UITextView) {
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak textView] notification in
                guard let textView,
                      let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let window = textView.window
                else { return }

                let keyboardFrameInView = textView.convert(endFrame, from: window.screen.coordinateSpace)
                let overlap = max(0, textView.bounds.maxY - keyboardFrameInView.minY)
                textView.contentInset.bottom = overlap
                textView.verticalScrollIndicatorInsets.bottom = overlap
            }
        }
    }
}
