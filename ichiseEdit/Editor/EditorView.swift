import SwiftUI

/// ドキュメント 1 件分の編集画面。
struct EditorView: View {
    @Binding var document: TextDocument
    var fileURL: URL?

    @StateObject private var proxy = TextViewProxy()
    @AppStorage("editor.fontSize") private var fontSize: Double = 17
    @AppStorage("editor.indentUsesSpaces") private var indentUsesSpaces = true
    @AppStorage("editor.indentWidth") private var indentWidth = 4
    @State private var statistics = TextStatistics()
    @State private var showPreview = false
    @State private var focusMode = false
    @State private var selectionCount = 0
    @State private var showStatistics = false

    private static let fontSizeRange: ClosedRange<Double> = 10...40
    private static let defaultFontSize: Double = 17

    private var mode: EditorMode {
        EditorMode.mode(for: fileURL)
    }

    var body: some View {
        HStack(spacing: 0) {
            TextView(
                text: $document.text,
                fontSize: fontSize,
                mode: mode,
                indentUsesSpaces: indentUsesSpaces,
                indentWidth: indentWidth,
                focusMode: focusMode,
                selectionCount: $selectionCount,
                proxy: proxy
            )
            if mode.isMarkdown && showPreview {
                Divider()
                MarkdownPreviewView(text: document.text)
            }
        }
        .ignoresSafeArea(.keyboard)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mode.isMarkdown {
                    Button {
                        showPreview.toggle()
                    } label: {
                        Label("Preview", systemImage: showPreview ? "eye.fill" : "eye")
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    markdownMenu
                }

                if mode.codeLanguage != nil {
                    indentMenu
                }

                Button {
                    focusMode.toggle()
                } label: {
                    Label("Focus", systemImage: focusMode ? "circle.circle.fill" : "circle.circle")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

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
                Button {
                    showStatistics = true
                } label: {
                    statusText
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showStatistics) {
                    StatisticsView(text: document.text)
                }
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

    private var statusText: some View {
        var status = Text("\(statistics.characters) characters / \(statistics.lines) lines")
        if selectionCount > 0 {
            status = status + Text(verbatim: " · ") + Text("\(selectionCount) selected")
        }
        if let language = mode.codeLanguage {
            status = status + Text(verbatim: " · \(language.name)")
        }
        return status
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var indentMenu: some View {
        Menu {
            Toggle(isOn: $indentUsesSpaces) {
                Label("Indent Using Spaces", systemImage: "arrow.right.to.line")
            }
            Picker("Tab Width", selection: $indentWidth) {
                Text(verbatim: "2").tag(2)
                Text(verbatim: "4").tag(4)
                Text(verbatim: "8").tag(8)
            }
        } label: {
            Label("Indent", systemImage: "increase.indent")
        }
    }

    private var markdownMenu: some View {
        Menu {
            Button {
                proxy.insertAtLineStart("# ")
            } label: {
                Label("Heading", systemImage: "number")
            }

            Button {
                proxy.wrapSelection(prefix: "**", suffix: "**", placeholder: "text")
            } label: {
                Label("Bold", systemImage: "bold")
            }
            .keyboardShortcut("b", modifiers: .command)

            Button {
                proxy.wrapSelection(prefix: "*", suffix: "*", placeholder: "text")
            } label: {
                Label("Italic", systemImage: "italic")
            }
            .keyboardShortcut("i", modifiers: .command)

            Button {
                proxy.wrapSelection(prefix: "`", suffix: "`", placeholder: "code")
            } label: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button {
                proxy.wrapSelection(prefix: "[", suffix: "](url)", placeholder: "title")
            } label: {
                Label("Link", systemImage: "link")
            }
        } label: {
            Label("Markdown", systemImage: "textformat")
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
