import SwiftUI
import UIKit

/// ISLISP の式を対話的に評価する REPL コンソール(シート表示)。
struct MacroREPLView: View {
    @ObservedObject var engine: MacroEngine
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            replBody
                .navigationTitle("REPL")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            UIPasteboard.general.string = engine.replTranscript
                            didCopy = true
                        } label: {
                            Label(didCopy ? "Copied" : "Copy All",
                                  systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        }
                        .disabled(engine.replLines.isEmpty)

                        Button(role: .destructive) {
                            engine.clearREPL()
                            didCopy = false
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(engine.replLines.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onChange(of: engine.replLines.count) { _ in
                    // 履歴が変わったらコピー済み表示を戻す
                    didCopy = false
                }
        }
    }

    private var replBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if engine.replLines.isEmpty {
                            Text(verbatim: "ISLISP REPL — 例: (+ 1 2) / (buffer-name) / (insert \"こんにちは\")")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(engine.replLines) { line in
                            Text(verbatim: line.text)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: engine.replLines.count) { _ in
                    if let last = engine.replLines.last {
                        withAnimation {
                            scroll.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Enter Expression", text: $input, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lineLimit(1...4)
                    .onSubmit(runInput)
                Button("Run", action: runInput)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        engine.isRunning
                            || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            .padding(10)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func runInput() {
        let source = input
        input = ""
        engine.evalREPL(source)
    }

    private func color(for kind: REPLLine.Kind) -> Color {
        switch kind {
        case .input: return .secondary
        case .output: return .primary
        case .error: return .red
        }
    }
}
