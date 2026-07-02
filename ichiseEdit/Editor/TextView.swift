import SwiftUI
import UIKit

/// エディタ本体。TextKit 2 で動作する UITextView のラッパー。
/// 注意: `layoutManager` にアクセスすると TextKit 1 にフォールバックするため、
/// レイアウト操作は必ず `textLayoutManager` 経由で行うこと。
struct TextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var isMarkdown: Bool = false
    var proxy: TextViewProxy?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: fontSize)
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
        }
        if fontChanged {
            textView.font = .systemFont(ofSize: fontSize)
            context.coordinator.applyHighlightIfNeeded(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        private var pendingHighlight: DispatchWorkItem?

        /// これを超える長さの文書ではハイライトを無効化する(入力性能を優先)
        private static let highlightLengthLimit = 200_000

        init(parent: TextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            scheduleHighlight(for: textView)
        }

        // MARK: - リスト・引用の自動継続

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard parent.isMarkdown, replacement == "\n", range.length == 0 else { return true }

            let ns = (textView.text ?? "") as NSString
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(
                &lineStart,
                end: &lineEnd,
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

        // MARK: - シンタックスハイライト

        func applyHighlightIfNeeded(to textView: UITextView) {
            guard parent.isMarkdown else { return }
            highlight(textView)
        }

        private func scheduleHighlight(for textView: UITextView) {
            guard parent.isMarkdown else { return }
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

            let theme = MarkdownTheme(fontSize: CGFloat(parent.fontSize))
            let tokens = MarkdownHighlighter.tokens(in: text)

            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributes(theme.baseAttributes, range: NSRange(location: 0, length: storage.length))
            for token in tokens {
                storage.addAttributes(theme.attributes(for: token.kind), range: token.range)
            }
            storage.endEditing()
            textView.typingAttributes = theme.baseAttributes
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
