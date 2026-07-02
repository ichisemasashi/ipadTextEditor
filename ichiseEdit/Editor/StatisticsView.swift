import SwiftUI

/// ステータスバーから開く文字数詳細のポップオーバー。
struct StatisticsView: View {
    let text: String

    @State private var statistics = DetailedTextStatistics()
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Statistics")
                .font(.headline)
                .padding(.bottom, 12)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                row("Characters", value: statistics.characters)
                row("Excluding Whitespace", value: statistics.charactersExcludingWhitespace)
                row("Words", value: statistics.words)
                row("Lines", value: statistics.lines)
                row("Paragraphs", value: statistics.paragraphs)
                GridRow {
                    Text("Manuscript Pages (400 chars)")
                        .foregroundStyle(.secondary)
                    Text(verbatim: pageString)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
            .opacity(isLoading ? 0.3 : 1)
        }
        .padding(20)
        .frame(minWidth: 280)
        .task {
            let source = text
            statistics = await Task.detached(priority: .userInitiated) {
                DetailedTextStatistics(counting: source)
            }.value
            isLoading = false
        }
    }

    private var pageString: String {
        String(format: "%.1f", statistics.manuscriptPages)
    }

    private func row(_ title: LocalizedStringKey, value: Int) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(value)")
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
