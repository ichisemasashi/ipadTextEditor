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

    // 記法挿入(wrapSelection / insertAtLineStart)は標準ライブラリ stdlib.lsp の
    // ISLISP 実装(wrap-selection / insert-at-line-start)へ移行した
}
