import SwiftUI

/// ドキュメント 1 件分の編集画面。
struct EditorView: View {
    @Binding var document: TextDocument

    @StateObject private var proxy = TextViewProxy()
    @AppStorage("editor.fontSize") private var fontSize: Double = 17
    @State private var statistics = TextStatistics()

    private static let fontSizeRange: ClosedRange<Double> = 10...40
    private static let defaultFontSize: Double = 17

    var body: some View {
        TextView(text: $document.text, fontSize: fontSize, proxy: proxy)
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        proxy.presentFindNavigator(showingReplace: false)
                    } label: {
                        Label("Find", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button {
                        proxy.presentFindNavigator(showingReplace: true)
                    } label: {
                        Label("Replace", systemImage: "arrow.2.squarepath")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    fontSizeMenu
                }
                ToolbarItem(placement: .status) {
                    Text("\(statistics.characters) characters / \(statistics.lines) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            // 全文走査(1MBで約17ms)を毎キーストロークで行うと入力が遅延するため、
            // 入力が止まってからバックグラウンドで再計算する
            .task(id: document.text) {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                let text = document.text
                statistics = await Task.detached(priority: .utility) {
                    TextStatistics(counting: text)
                }.value
            }
    }

    private var fontSizeMenu: some View {
        Menu {
            Button {
                fontSize = min(fontSize + 1, Self.fontSizeRange.upperBound)
            } label: {
                Label("Increase Text Size", systemImage: "textformat.size.larger")
            }
            .keyboardShortcut("+", modifiers: .command)

            Button {
                fontSize = max(fontSize - 1, Self.fontSizeRange.lowerBound)
            } label: {
                Label("Decrease Text Size", systemImage: "textformat.size.smaller")
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Text Size") {
                fontSize = Self.defaultFontSize
            }
            .keyboardShortcut("0", modifiers: .command)
        } label: {
            Label("Text Size", systemImage: "textformat.size")
        }
    }
}
