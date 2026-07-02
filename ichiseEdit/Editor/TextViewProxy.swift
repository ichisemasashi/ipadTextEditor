import UIKit

/// SwiftUI 側から UITextView の機能(検索パネル表示など)を呼び出すための橋渡し。
final class TextViewProxy: ObservableObject {
    weak var textView: UITextView?

    /// システム標準の検索(置換)パネルを表示する。
    func presentFindNavigator(showingReplace: Bool) {
        guard let textView else { return }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        textView.findInteraction?.presentFindNavigator(showingReplace: showingReplace)
    }
}
