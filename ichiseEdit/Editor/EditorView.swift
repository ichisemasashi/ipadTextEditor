import SwiftUI

/// ドキュメント 1 件分の編集画面。
struct EditorView: View {
    @Binding var document: TextDocument

    var body: some View {
        TextView(text: $document.text)
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItem(placement: .status) {
                    Text("\(document.text.count) 文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
    }
}
