import SwiftUI

/// Markdown プレビュー。Apple 標準の AttributedString(markdown:) でパースし、
/// ブロック(見出し・段落・コード・リスト・引用)を SwiftUI で描画する。
/// 外部依存なし。表・画像は v1.1 では非対応。
struct MarkdownPreviewView: View {
    let text: String

    @State private var blocks: [Block] = []

    struct Block: Identifiable {
        enum Kind {
            case heading(Int)
            case paragraph
            case codeBlock
            case listItem(prefix: String, indent: Int)
            case blockquote
            case divider
        }

        let id: Int
        let kind: Kind
        let content: AttributedString
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    render(block)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        // 入力中の再パースを避けるため、テキストが落ち着いてから更新する
        .task(id: text) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let source = text
            blocks = await Task.detached(priority: .utility) {
                Self.parse(source)
            }.value
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.content)
                .font(headingFont(level))
                .bold()
        case .paragraph:
            Text(block.content)
        case .codeBlock:
            Text(block.content)
                .font(.system(.callout, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        case .listItem(let prefix, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prefix)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(block.content)
            }
            .padding(.leading, CGFloat(max(0, indent - 1)) * 20)
        case .blockquote:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(block.content)
                    .foregroundStyle(.secondary)
            }
        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    // MARK: - パース

    static func parse(_ text: String) -> [Block] {
        guard !text.isEmpty else { return [] }
        guard let attributed = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: false,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return [Block(id: 0, kind: .paragraph, content: AttributedString(text))]
        }

        // 同じ PresentationIntent を持つ連続した run を 1 ブロックにまとめる
        var groups: [(intent: PresentationIntent?, content: AttributedString)] = []
        for run in attributed.runs {
            let slice = AttributedString(attributed[run.range])
            if !groups.isEmpty, groups[groups.count - 1].intent == run.presentationIntent {
                groups[groups.count - 1].content += slice
            } else {
                groups.append((run.presentationIntent, slice))
            }
        }

        return groups.enumerated().map { index, group in
            Block(id: index, kind: kind(for: group.intent), content: trimmed(group.content))
        }
    }

    private static func kind(for intent: PresentationIntent?) -> Block.Kind {
        guard let intent else { return .paragraph }

        var headingLevel: Int?
        var isCode = false
        var isQuote = false
        var listOrdinal: Int?
        var isOrdered = false
        var listDepth = 0
        var isDivider = false

        for component in intent.components {
            switch component.kind {
            case .header(let level):
                headingLevel = level
            case .codeBlock:
                isCode = true
            case .blockQuote:
                isQuote = true
            case .listItem(let ordinal):
                listOrdinal = ordinal
            case .orderedList:
                isOrdered = true
                listDepth += 1
            case .unorderedList:
                listDepth += 1
            case .thematicBreak:
                isDivider = true
            default:
                break
            }
        }

        if isDivider { return .divider }
        if let level = headingLevel { return .heading(level) }
        if isCode { return .codeBlock }
        if let ordinal = listOrdinal {
            return .listItem(prefix: isOrdered ? "\(ordinal)." : "•", indent: listDepth)
        }
        if isQuote { return .blockquote }
        return .paragraph
    }

    private static func trimmed(_ content: AttributedString) -> AttributedString {
        var result = content
        while let last = result.characters.last, last.isNewline {
            result.characters.removeLast()
        }
        return result
    }
}
