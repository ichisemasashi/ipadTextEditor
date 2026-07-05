import SwiftUI

/// ドキュメント 1 件分の編集画面。
struct EditorView: View {
    @Binding var document: TextDocument
    var fileURL: URL?

    @StateObject private var proxy = TextViewProxy()
    @StateObject private var macroEngine = MacroEngine()
    @AppStorage("editor.fontSize") private var fontSize: Double = 17
    @AppStorage("editor.indentUsesSpaces") private var indentUsesSpaces = true
    @AppStorage("editor.indentWidth") private var indentWidth = 4
    @AppStorage("editor.wordWrap") private var wordWrap = true
    @State private var statistics = TextStatistics()
    @State private var showPreview = false
    @State private var focusMode = false
    @State private var selectionCount = 0
    @State private var showStatistics = false
    @State private var showREPL = false
    @State private var showManual = false
    @State private var syntaxOverride: SyntaxChoice?

    private static let fontSizeRange: ClosedRange<Double> = 10...40
    private static let defaultFontSize: Double = 17

    private var mode: EditorMode {
        syntaxOverride?.mode ?? EditorMode.mode(for: fileURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TextView(
                    text: $document.text,
                    fontSize: fontSize,
                    mode: mode,
                    indentUsesSpaces: indentUsesSpaces,
                    indentWidth: indentWidth,
                    focusMode: focusMode,
                    wordWrap: wordWrap,
                    selectionCount: $selectionCount,
                    proxy: proxy,
                    macroEngine: macroEngine
                )
                if mode.isMarkdown && showPreview {
                    Divider()
                    MarkdownPreviewView(text: document.text)
                }
            }
            .ignoresSafeArea(.keyboard)
            Divider()
            statusBar
        }
        .overlay(alignment: .bottom) {
            if let toast = macroEngine.toastMessage {
                Text(verbatim: toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .task(id: macroEngine.toastMessage) {
            guard macroEngine.toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            macroEngine.toastMessage = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    proxy.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }

                Button {
                    proxy.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }

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

                macroMenu

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
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsView(text: document.text)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showREPL) {
            MacroREPLView(engine: macroEngine)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            macroEngine.proxy = proxy
            let name = fileURL?.lastPathComponent ?? ""
            macroEngine.documentName = { name }
            macroEngine.loadIfNeeded()
        }
        .alert(
            "Macro Error",
            isPresented: Binding(
                get: { macroEngine.errorMessage != nil },
                set: { if !$0 { macroEngine.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: macroEngine.errorMessage ?? "")
        }
        .sheet(isPresented: $showManual) {
            ManualView()
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

    /// エディタ下部に常設するステータスバー。タップで統計を表示する。
    private var statusBar: some View {
        Button {
            showStatistics = true
        } label: {
            HStack(spacing: 0) {
                statusText
                Spacer(minLength: 8)
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
    }

    private var statusText: some View {
        var status = Text("\(statistics.characters) characters / \(statistics.lines) lines")
        if selectionCount > 0 {
            status = status + Text(verbatim: " · ") + Text("\(selectionCount) selected")
        }
        status = status + Text(verbatim: " · ") + Text(verbatim: SyntaxChoice.current(mode).displayName)
        return status
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var macroMenu: some View {
        Menu {
            ForEach(macroEngine.commands) { command in
                Button(command.name) {
                    macroEngine.run(command)
                }
                .keyboardShortcut(command.shortcut?.keyboardShortcut)
                .disabled(macroEngine.isRunning)
            }
            // 選択範囲コマンド(編集メニューにも出るが、見つけやすいようここにも置く)
            if !macroEngine.selectionCommands.isEmpty {
                Divider()
                ForEach(macroEngine.selectionCommands) { command in
                    Button {
                        macroEngine.runSelection(command)
                    } label: {
                        Label(command.name, systemImage: "text.cursor")
                    }
                    .keyboardShortcut(command.shortcut?.keyboardShortcut)
                    .disabled(macroEngine.isRunning || selectionCount == 0)
                }
            }
            if !macroEngine.commands.isEmpty {
                Divider()
            }
            Button {
                showREPL.toggle()
            } label: {
                Label("Open REPL", systemImage: showREPL ? "terminal.fill" : "terminal")
            }
            Button {
                macroEngine.reload()
            } label: {
                Label("Reload Macros", systemImage: "arrow.clockwise")
            }
            Button {
                showManual = true
            } label: {
                Label("Macro Manual", systemImage: "book")
            }
        } label: {
            Label("Macros", systemImage: "hammer")
        }
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

    /// Markdown 編集コマンド。実装は標準ライブラリ(stdlib.lsp)の ISLISP 関数
    private var markdownMenu: some View {
        Menu {
            Button {
                macroEngine.runFunction(named: "md-heading")
            } label: {
                Label("Heading", systemImage: "number")
            }

            Button {
                macroEngine.runFunction(named: "md-bold")
            } label: {
                Label("Bold", systemImage: "bold")
            }
            .keyboardShortcut("b", modifiers: .command)

            Button {
                macroEngine.runFunction(named: "md-italic")
            } label: {
                Label("Italic", systemImage: "italic")
            }
            .keyboardShortcut("i", modifiers: .command)

            Button {
                macroEngine.runFunction(named: "md-code")
            } label: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button {
                macroEngine.runFunction(named: "md-link")
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

            Divider()

            Toggle(isOn: $wordWrap) {
                Label("Wrap Lines", systemImage: "arrow.turn.down.left")
            }

            syntaxMenu
        } label: {
            Label("Display", systemImage: "textformat.size")
        }
    }

    /// 拡張子に関わらずハイライトの文法を手動で切り替える
    private var syntaxMenu: some View {
        let current = SyntaxChoice.current(mode)
        return Menu {
            Picker("Syntax", selection: syntaxSelection) {
                Label(SyntaxChoice.plainText.displayName, systemImage: "doc.plaintext")
                    .tag(SyntaxChoice.plainText)
                Label(SyntaxChoice.markdown.displayName, systemImage: "text.badge.checkmark")
                    .tag(SyntaxChoice.markdown)
                ForEach(LanguageRegistry.allLanguages, id: \.name) { language in
                    Text(verbatim: language.name).tag(SyntaxChoice.code(language.name))
                }
            }
        } label: {
            Label("Syntax", systemImage: "chevron.left.forwardslash.chevron.right")
            Text(verbatim: current.displayName)
        }
    }

    /// 文法ピッカーの選択(選ぶと override を更新)
    private var syntaxSelection: Binding<SyntaxChoice> {
        Binding(
            get: { SyntaxChoice.current(mode) },
            set: { syntaxOverride = $0 }
        )
    }
}
