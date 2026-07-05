import UIKit

/// SwiftUI 側から UITextView の機能(検索パネル表示・記法挿入など)を呼び出すための橋渡し。
final class TextViewProxy: ObservableObject {
    weak var textView: UITextView?

    /// 取り消し/やり直し(ソフトウェアキーボードには ⌘Z がないため、ツールバーから使う)
    func undo() {
        textView?.undoManager?.undo()
    }

    func redo() {
        textView?.undoManager?.redo()
    }

    /// システム標準の検索(置換)パネルを表示する。
    func presentFindNavigator(showingReplace: Bool) {
        guard let textView else { return }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        textView.findInteraction?.presentFindNavigator(showingReplace: showingReplace)
    }

    /// 選択範囲を prefix/suffix で囲む(選択がなければ placeholder を挿入して選択状態にする)。
    func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        guard let textView else { return }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        guard let selection = textView.selectedTextRange else { return }

        let selectedText = textView.text(in: selection) ?? ""
        let core = selectedText.isEmpty ? placeholder : selectedText
        let selectionStart = textView.offset(from: textView.beginningOfDocument, to: selection.start)

        textView.replace(selection, withText: prefix + core + suffix)

        // 挿入した本文部分を選択し直す(すぐ書き換えられるように)
        if let start = textView.position(
            from: textView.beginningOfDocument,
            offset: selectionStart + (prefix as NSString).length
        ),
            let end = textView.position(from: start, offset: (core as NSString).length),
            let range = textView.textRange(from: start, to: end) {
            textView.selectedTextRange = range
        }
    }

    /// 現在行の行頭に文字列を挿入する(見出し記法用)。
    func insertAtLineStart(_ prefix: String) {
        guard let textView else { return }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        guard let selection = textView.selectedTextRange else { return }

        let caret = textView.offset(from: textView.beginningOfDocument, to: selection.start)
        let ns = (textView.text ?? "") as NSString
        var lineStart = 0
        ns.getLineStart(&lineStart, end: nil, contentsEnd: nil, for: NSRange(location: caret, length: 0))

        if let position = textView.position(from: textView.beginningOfDocument, offset: lineStart),
           let range = textView.textRange(from: position, to: position) {
            textView.selectedTextRange = range
            textView.insertText(prefix)
            // カーソルを元の位置(挿入分ずらした場所)へ戻す
            if let restored = textView.position(
                from: textView.beginningOfDocument,
                offset: caret + (prefix as NSString).length
            ) {
                textView.selectedTextRange = textView.textRange(from: restored, to: restored)
            }
        }
    }
}
