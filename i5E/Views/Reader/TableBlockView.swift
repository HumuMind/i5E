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

    /// 整张表只有一个格子有内容（常见于"文字 + 插图"的排版表格）时，
    /// 当作容器直接铺开，不按列宽压缩。
    private var soleContentCell: TableCell? {
        let cells = (block.rows ?? []).flatMap(\.cells)
        let filled = cells.filter {
            !$0.plainText.trimmingCharacters(in: .whitespaces).isEmpty || $0.hasImage
        }
        return filled.count == 1 ? filled[0] : nil
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
        let available =
            min(availableWidth, metrics.measure(forAvailable: availableWidth))
            - TableLayoutCalculator.horizontalPadding
        var widths = TableLayoutCalculator.widths(
            normalized, fontSize: size, available: available)
        // 源页给了显式宽度就按它缩放：px 折算成 pt，百分比按可用宽度算
        if let target = targetWidth(available: available) {
            let total = widths.reduce(0, +)
            if total > 0, abs(total - target) > 1 {
                widths = widths.map { $0 * target / total }
            }
        }
        // 「文字 | 插图」两列排版表：图片列固定拿 45%，否则文字列会把宽度吃光
        if widths.count == 2,
            let imageColumn = normalized.rows?.first?.cells.firstIndex(where: \.hasImage)
        {
            let imageWidth = max(160, available * 0.45)
            let rest = max(120, available - imageWidth)
            widths = imageColumn == 0 ? [imageWidth, rest] : [rest, imageWidth]
        }
        return Layout(
            block: normalized, widths: widths, totalWidth: widths.reduce(0, +), fontSize: size)
    }

    /// 源页给表格写的宽度（px 或百分比），没有就返回 nil（按内容宽度）。
    private func targetWidth(available: CGFloat) -> CGFloat? {
        if let percent = block.wp, percent > 0 {
            return available * CGFloat(percent) / 100
        }
        if let px = block.w, px > 0 {
            return min(CGFloat(px) * 0.75, available)
        }
        return nil
    }

    /// 源页里 basic / center / part 这几类表格没有边框；数据块里的表格同样无边框
    private var isBorderless: Bool {
        // 源页默认不画格子：只有写了 border 属性、页面 CSS 统一加边框、
        // 或用了 basic/center/part 这类明确无边框的表格才有区别
        if ClassStyle.isBorderlessTable(block.cls) { return true }
        if ancestors.contains("stat-block") { return true }
        return block.bd != 1
    }

    @ViewBuilder
    var body: some View {
        let layout = layout
        // 单行单列的表格在源页里是排版容器，不是数据表
        if let cell = soleContentCell {
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
        VStack(alignment: .leading, spacing: 6) {
            if let caption = block.caption, !caption.isEmpty {
                // caption 用整行宽度居中：表格可能比它窄，挤在表格宽度里会折行
                Text(caption)
                    .font(.system(size: layout.fontSize, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            tableRow(layout)
        }
        // 撑满可用宽度，caption 才有整行可居中（否则会跟着窄表格一起被压窄）
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(_ layout: Layout) -> some View {
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
        .frame(maxWidth: .infinity, alignment: block.al == "c" ? .center : .leading)
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

    private func cellTextAlignment(_ cell: TableCell) -> TextAlignment {
        switch cell.al {
        case "c": .center
        case "r": .trailing
        default: .leading
        }
    }

    private func cellFrameAlignment(_ cell: TableCell) -> Alignment {
        switch cell.al {
        case "c": .top
        case "r": .topTrailing
        default: .topLeading
        }
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

    /// 单元格里的一个块。含图片时要单独渲染——`AttributedText` 只处理文字 run，
    /// 图片（常见于"图文并排"的排版表格）会被丢掉。
    @ViewBuilder
    private func cellBlock(
        _ inner: Block, cell: TableCell, layout: Layout, cellWidth: CGFloat
    ) -> some View {
        // 单元格里可能是整段嵌套结构（有的页把整个数据块放进一格），
        // 这种情况必须交给 BlockView 递归渲染，不能只取 runs
        if !inner.blocksOrEmpty.isEmpty {
            BlockView(
                block: inner, ancestors: ancestors, highlight: nil, availableWidth: cellWidth)
        } else if inner.runsOrEmpty.contains(where: { $0.img != nil }) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Self.pieces(inner.runsOrEmpty).enumerated()), id: \.offset) {
                    _, piece in
                    switch piece {
                    case .text(let runs):
                        Text(
                            AttributedText.make(
                                runs, size: layout.fontSize, bold: cell.header == true,
                                theme: theme)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let run):
                        ContentImageView(run: run, maxWidth: cellWidth)
                    }
                }
            }
        } else {
            Text(
                AttributedText.make(
                    inner.runsOrEmpty, size: layout.fontSize, bold: cell.header == true,
                    theme: theme)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum Piece {
        case text([Run])
        case image(Run)
    }

    private static func pieces(_ runs: [Run]) -> [Piece] {
        var result: [Piece] = []
        var buffer: [Run] = []
        for run in runs {
            if run.img != nil {
                if !buffer.isEmpty { result.append(.text(buffer)); buffer = [] }
                result.append(.image(run))
            } else {
                buffer.append(run)
            }
        }
        if !buffer.isEmpty { result.append(.text(buffer)) }
        return result
    }

    private func cellView(_ cell: TableCell, at index: Int, layout: Layout) -> some View {
        let span = max(1, cell.colspan ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                cellBlock(
                    inner, cell: cell, layout: layout,
                    cellWidth: width(at: index, span: span, layout: layout))
            }
        }
        .multilineTextAlignment(cellTextAlignment(cell))
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(
            width: width(at: index, span: span, layout: layout),
            alignment: cellFrameAlignment(cell)
        )
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
