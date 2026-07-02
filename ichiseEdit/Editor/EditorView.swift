import SwiftUI

/// ドキュメント 1 件分の編集画面。
struct EditorView: View {
    @Binding var document: TextDocument

    @StateObject private var proxy = TextViewProxy()
    @AppStorage("editor.fontSize") private var fontSize: Double = 17

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
                    Text("\(document.text.count) characters / \(lineCount) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
    }

    private var lineCount: Int {
        if document.text.isEmpty { return 1 }
        return document.text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
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
