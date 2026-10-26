import ContentKit
import SwiftUI

struct TableBlockView: View {
    @Environment(\.readingMetrics) private var metrics
    let block: Block
    var ancestors: Set<String> = []
    var availableWidth: CGFloat

    @Environment(\.readingTheme) private var theme

    /// 一次算好的排版结果。
    ///
    /// 列宽原来写成计算属性，每渲染一个单元格就重算一遍；而算一次要对全表做
    /// CoreText 测量，一百多行的表格因此变成平方级，卡好几秒。
    private struct Layout {
        var block: Block
        var widths: [CGFloat]
        var totalWidth: CGFloat
        var fontSize: CGFloat
    }

    private var layout: Layout {
        let normalized = TableLayoutCalculator.normalize(block)
        let count = TableLayoutCalculator.columnCount(normalized)
        let size: CGFloat =
            switch count {
            case ...2: metrics.bodySize
            case 3...4: 16
            default: 13
            }
        let widths = TableLayoutCalculator.widths(
            normalized, fontSize: size,
            available: min(availableWidth, metrics.measure)
                - TableLayoutCalculator.horizontalPadding)
        return Layout(
            block: normalized, widths: widths, totalWidth: widths.reduce(0, +), fontSize: size)
    }

    /// 源页里 basic / center / part 这几类表格没有边框；数据块里的表格同样无边框
    private var isBorderless: Bool {
        ClassStyle.isBorderlessTable(block.cls) || ancestors.contains("stat-block")
    }

    @ViewBuilder
    var body: some View {
        let layout = layout
        // 单行单列的表格在源页里是排版容器，不是数据表
        if layout.block.rows?.count == 1, let cell = layout.block.rows?.first?.cells.first {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                    BlockView(
                        block: inner, ancestors: ancestors, highlight: nil,
                        availableWidth: availableWidth)
                }
            }
            .padding(.vertical, 6)
        } else {
            tableChrome(layout)
        }
    }

    private func tableChrome(_ layout: Layout) -> some View {
        HStack(spacing: 0) {
            tableBody(layout)
                .frame(width: layout.totalWidth, alignment: .leading)
                .overlay {
                    if !isBorderless {
                        Rectangle().stroke(theme.border, lineWidth: 0.5)
                    }
                }
                .clipShape(.rect(cornerRadius: 4))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.bottom, 12)
    }

    private func tableBody(_ layout: Layout) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array((layout.block.rows ?? []).enumerated()), id: \.offset) { _, row in
                if isGroupRow(row) {
                    groupRow(row, layout: layout)
                } else {
                    // 顶部对齐：否则短单元格会被垂直居中，灰底看着高低不齐
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            cellView(cell, at: index, layout: layout)
                        }
                    }
                    .frame(width: layout.totalWidth, alignment: .topLeading)
                    .background(rowColor(row))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowLabel(row, layout: layout))
                }
            }
        }
    }

    /// 分组行：只有第一格有字、其余为空、文字不长（如装备表里的「弹药」「奥术法器」）。
    private func isGroupRow(_ row: ContentKit.TableRow) -> Bool {
        guard row.cells.count >= 2 else { return false }
        let others = row.cells.dropFirst()
        guard others.allSatisfy({ $0.plainText.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return false }
        let first = row.cells[0].plainText.trimmingCharacters(in: .whitespaces)
        return !first.isEmpty && first.count <= 18
    }

    private func groupRow(_ row: ContentKit.TableRow, layout: Layout) -> some View {
        // 源页的分组行是斜体（`<i>`），这里直接加粗并斜体
        Text(row.cells[0].plainText.trimmingCharacters(in: .whitespaces))
            .font(.system(size: layout.fontSize, weight: .semibold))
            .italic()
            .foregroundStyle(theme.text)
            .frame(width: layout.totalWidth, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(theme.border.opacity(0.35))
    }

    /// 表格行的朗读文本：「物品名：火球术，环阶：三环」。
    private func rowLabel(_ row: ContentKit.TableRow, layout: Layout) -> String {
        row.cells.enumerated().compactMap { index, cell in
            let text = cell.blocks.compactMap { $0.runsOrEmpty.compactMap(\.t).joined() }
                .joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let header = layout.block.rows?.first?.cells
            let name = (header.flatMap { index < $0.count ? $0[index] : nil })
                .map { $0.blocks.compactMap { $0.runsOrEmpty.compactMap(\.t).joined() }.joined() }
            return (name?.isEmpty == false ? name! + "：" : "") + text
        }
        .joined(separator: "，")
    }

    private func rowColor(_ row: ContentKit.TableRow) -> Color {
        guard let hex = row.bg else { return .clear }
        return background(from: hex)
    }

    private func background(from hex: String) -> Color {
        guard let rgb = RGB(hexOrRGB: hex) else { return .clear }
        return theme.adjustedBackground(rgb)
    }

    private func cellBackground(_ cell: TableCell) -> Color {
        if let hex = ClassStyle.cellBackground(cell.cls) {
            return background(from: hex)
        }
        guard let hex = cell.bg else { return .clear }
        return background(from: hex)
    }

    private func width(at index: Int, span: Int, layout: Layout) -> CGFloat {
        let widths = layout.widths
        let upper = min(widths.count, index + span)
        guard index < upper else { return widths.last ?? 0 }
        return widths[index..<upper].reduce(0, +)
    }

    private func cellView(_ cell: TableCell, at index: Int, layout: Layout) -> some View {
        let span = max(1, cell.colspan ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                Text(
                    AttributedText.make(
                        inner.runsOrEmpty, size: layout.fontSize, bold: cell.header == true,
                        theme: theme)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: width(at: index, span: span, layout: layout), alignment: .topLeading)
        // 撑满行高：源页的 td 背景是整格高度，矮的格子不撑开就会出现灰底高低不齐
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cellBackground(cell))
        .overlay {
            if !isBorderless {
                Rectangle().stroke(theme.border, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - 富文本
