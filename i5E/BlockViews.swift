import SwiftUI
import ContentKit

/// 单个 block 的渲染。表格与图片是简化实现，见文件末尾说明。
struct BlockView: View {
    let block: Block
    var highlight: String?

    var body: some View {
        switch block.type {
        case "h":
            heading
        case "p", "dt":
            JustifiedText(runs: block.runsOrEmpty, fontSize: Reading.bodySize, highlight: highlight)
                .padding(.bottom, Reading.bodySize * 0.95)
        case "dd":
            JustifiedText(runs: block.runsOrEmpty, fontSize: Reading.bodySize, highlight: highlight)
                .padding(.leading, 24)
                .padding(.bottom, Reading.bodySize * 0.6)
        case "list":
            ListBlockView(block: block, highlight: highlight)
        case "table":
            TableBlockView(block: block)
        case "quote":
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(.quaternary).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(block.blocksOrEmpty.enumerated()), id: \.offset) { _, inner in
                        BlockView(block: inner, highlight: highlight)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 12)
        case "div":
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(block.blocksOrEmpty.enumerated()), id: \.offset) { _, inner in
                    BlockView(block: inner, highlight: highlight)
                }
            }
        case "pre":
            Text(block.text ?? "")
                .font(.system(size: 14, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
                .padding(.bottom, 16)
        case "hr":
            Divider().padding(.vertical, 20)
        default:
            EmptyView()
        }
    }

    private var heading: some View {
        let level = block.level ?? 2
        let (scale, weight): (CGFloat, Font.Weight) =
            switch level {
            case 1: (1.6, .bold)
            case 2: (1.35, .bold)
            case 3: (1.2, .semibold)
            case 4: (1.25, .semibold)  // 上游用 h4 做法术/怪物条目标题
            case 5: (1.1, .semibold)
            default: (1.0, .semibold)
            }
        return Text(
            AttributedText.make(
                block.runsOrEmpty, size: Reading.bodySize * scale,
                bold: weight == .bold, fallbackColor: .primary)
        )
        .lineSpacing(Reading.bodySize * scale * 0.4)
        .padding(.top, level <= 2 ? 26 : 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 列表

private struct ListBlockView: View {
    let block: Block
    var highlight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(index))
                        .font(.custom("Songti SC", size: Reading.bodySize))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.runs.isEmpty {
                            Text(
                                AttributedText.make(
                                    item.runs, size: Reading.bodySize,
                                    highlight: highlight)
                            )
                            .lineSpacing(Reading.lineSpacing)
                        }
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, inner in
                            BlockView(block: inner, highlight: highlight)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, Reading.bodySize * 0.95)
    }

    private func marker(_ index: Int) -> String {
        (block.ordered == true) ? "\(index + 1)." : "•"
    }
}

// MARK: - 表格

/// 简化实现：等宽列、不做合并单元格、字号按列数降档。
/// 完整规则见 0011（19→16→13 阶梯、fixed 布局、超宽换行）。
private struct TableBlockView: View {
    let block: Block

    private var columnCount: Int {
        (block.rows ?? []).map { $0.cells.reduce(0) { $0 + ($1.colspan ?? 1) } }.max() ?? 0
    }

    private var fontSize: CGFloat {
        switch columnCount {
        case ...2: Reading.bodySize
        case 3...4: 16
        default: 13
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((block.rows ?? []).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                }
            }
        }
        .background(Color(hex: "#ffffff") ?? .clear)
        .overlay(Rectangle().stroke(.quaternary, lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: 4))
        .padding(.vertical, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellView(_ cell: TableCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                Text(
                    AttributedText.make(
                        inner.runsOrEmpty, size: fontSize,
                        bold: cell.header == true)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: cell.bg ?? "") ?? .clear)
        .overlay(Rectangle().stroke(.quaternary, lineWidth: 0.5))
    }
}

// MARK: - 富文本

enum AttributedText {
    /// 把 run 序列转成 AttributedString。保留颜色、粗斜体、下划线。
    /// 字号一律用传入值——源页的绝对字号（8–22pt）在阅读模式里不采用。
    static func make(
        _ runs: [Run], size: CGFloat, bold: Bool = false,
        fallbackColor: Color = .primary, highlight: String? = nil
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            guard let text = run.t, !text.isEmpty else { continue }
            let weight: Font.Weight = (bold || run.b == 1) ? .bold : .regular
            var font = Font.custom("Songti SC", size: size).weight(weight)
            if run.i == 1 { font = font.italic() }
            let color = run.c.flatMap { Color(hex: $0) } ?? fallbackColor

            for (segment, hit) in split(text, by: highlight) {
                var piece = AttributedString(segment)
                piece.font = font
                piece.foregroundColor = color
                if hit { piece.backgroundColor = Color.accentColor.opacity(0.22) }
                if run.u == 1 { piece.underlineStyle = .single }
                if run.s == 1 { piece.strikethroughStyle = .single }
                result.append(piece)
            }
        }
        return result
    }

    /// 把文本按查询词切成 (片段, 是否命中)；没有高亮词时返回整段。
    static func split(_ text: String, by needle: String?) -> [(String, Bool)] {
        guard let needle, !needle.isEmpty else { return [(text, false)] }
        var parts: [(String, Bool)] = []
        var rest = Substring(text)
        while let range = rest.range(of: needle, options: .caseInsensitive) {
            if range.lowerBound > rest.startIndex {
                parts.append((String(rest[rest.startIndex..<range.lowerBound]), false))
            }
            parts.append((String(rest[range]), true))
            rest = rest[range.upperBound...]
        }
        if !rest.isEmpty { parts.append((String(rest), false)) }
        return parts
    }
}

extension Color {
    /// 接受 `#rrggbb` 或 `rrggbb`。
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1)
    }
}
