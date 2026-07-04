import SwiftUI

/// アプリ内マニュアル表示。バンドルした Markdown を読み込んで表示する。
struct ManualView: View {
    @Environment(\.dismiss) private var dismiss

    private let document: HelpDocument

    init(document: HelpDocument = ManualView.loadBundledManual()) {
        self.document = document
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(document.blocks) { item in
                        block(item.block)
                    }
                }
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Macro Manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func block(_ block: HelpDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .bold(level <= 3)
                .padding(.top, level <= 2 ? 10 : 4)

        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)

        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .divider:
            Divider().padding(.vertical, 4)
        }
    }

    private func tableView(headers: [AttributedString], rows: [[AttributedString]]) -> some View {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                ForEach(0..<columns, id: \.self) { col in
                    Text(col < headers.count ? headers[col] : AttributedString(""))
                        .font(.subheadline.bold())
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        Text(col < row.count ? row[col] : AttributedString(""))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    /// アプリにバンドルした macro-manual.md を読み込む
    static func loadBundledManual() -> HelpDocument {
        guard let url = Bundle.main.url(forResource: "macro-manual", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return HelpDocument(markdown: "# マニュアルを読み込めませんでした")
        }
        return HelpDocument(markdown: text)
    }
}
