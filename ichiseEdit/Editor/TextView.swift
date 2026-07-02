import SwiftUI
import UIKit

/// エディタ本体。TextKit 2 で動作する UITextView のラッパー。
/// 注意: `layoutManager` にアクセスすると TextKit 1 にフォールバックするため、
/// レイアウト操作は必ず `textLayoutManager` 経由で行うこと。
struct TextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var mode: EditorMode = .plainText
    var indentUsesSpaces: Bool = true
    var indentWidth: Int = 4
    var proxy: TextViewProxy?

    private var baseFont: UIFont {
        mode.codeLanguage != nil
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
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

        context.coordinator.applyHighlightIfNeeded(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let fontChanged = textView.font?.pointSize != CGFloat(fontSize)
        context.coordinator.parent = self

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

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        var gutter: LineNumberGutterView?
        private var pendingHighlight: DispatchWorkItem?

        /// これを超える長さの文書ではハイライトを無効化する(入力性能を優先)
        private static let highlightLengthLimit = 200_000

        init(parent: TextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            scheduleHighlight(for: textView)
            gutter?.rebuildLineStarts(text: textView.text ?? "")
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gutter?.synchronize()
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
            guard parent.mode != .plainText else { return }
            highlight(textView)
        }

        private func scheduleHighlight(for textView: UITextView) {
            guard parent.mode != .plainText else { return }
            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.highlight(textView)
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
                return
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
