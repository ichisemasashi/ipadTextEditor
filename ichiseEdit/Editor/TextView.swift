import SwiftUI
import UIKit

/// エディタ本体。TextKit 2 で動作する UITextView のラッパー。
/// 注意: `layoutManager` にアクセスすると TextKit 1 にフォールバックするため、
/// レイアウト操作は必ず `textLayoutManager` 経由で行うこと。
struct TextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: Double
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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // 入力のたびに再設定するとカーソル位置が失われるため、差分がある時のみ反映する
        if textView.text != text {
            textView.text = text
        }
        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = .systemFont(ofSize: fontSize)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
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
