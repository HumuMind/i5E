import ContentKit
import SwiftUI

struct TableBlockView: View {
    @Environment(\.readingMetrics) private var metrics
    let block: Block
    var ancestors: Set<String> = []
    var availableWidth: CGFloat

    @Environment(\.readingTheme) private var theme
    @Environment(\.mentionLevel) private var mentionLevel

    /// 一次算好的排版结果。
    ///
    /// 列宽原来写成计算属性，每渲染一个单元格就重算一遍；而算一次要对全表做
    /// CoreText 测量，一百多行的表格因此变成平方级，卡好几秒。
    private struct Layout {
        var block: Block
        /// 合并格落位：colspan/rowspan 展开后每格从第几列开始
        var grid: TableGrid
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
        let grid = TableGrid(normalized)
        let count = grid.columnCount
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
            block: normalized, grid: grid, widths: widths, totalWidth: widths.reduce(0, +),
            fontSize: size)
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
            ForEach(Array((layout.block.rows ?? []).enumerated()), id: \.offset) { index, row in
                if isGroupRow(row) {
                    groupRow(row, layout: layout)
                } else {
                    // 顶部对齐：否则短单元格会被垂直居中，灰底看着高低不齐
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(
                            Array(layout.grid.slots(in: index).enumerated()), id: \.offset
                        ) { _, slot in
                            switch slot {
                            case .cell(let placement):
                                cellView(
                                    placement.cell, column: placement.column,
                                    span: placement.colspan, layout: layout)
                            case .hole(let column, let colspan):
                                // 被上方 rowspan 盖住、或行尾缺列：留空但占住列宽，
                                // 后面的格子才不会被顶到左边
                                Color.clear.frame(
                                    width: width(at: column, span: colspan, layout: layout))
                            }
                        }
                    }
                    .frame(width: layout.totalWidth, alignment: .topLeading)
                    .background(rowColor(row))
                    .background(alternatingFill(row, layout: layout))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowLabel(index, layout: layout))
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
    private func rowLabel(_ rowIndex: Int, layout: Layout) -> String {
        layout.grid.slots(in: rowIndex).compactMap { slot in
            guard case .cell(let placement) = slot else { return nil }
            let text = placement.cell.blocks
                .compactMap { $0.runsOrEmpty.compactMap(\.t).joined() }
                .joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let name = columnTitle(placement.column, layout: layout)
            return (name?.isEmpty == false ? name! + "：" : "") + text
        }
        .joined(separator: "，")
    }

    /// 某列的标题（取表头行里覆盖该列的那格）。
    private func columnTitle(_ column: Int, layout: Layout) -> String? {
        guard let header = layout.grid.rows.first else { return nil }
        for placement in header
        where column >= placement.column && column < placement.column + placement.colspan {
            return placement.cell.blocks
                .compactMap { $0.runsOrEmpty.compactMap(\.t).joined() }.joined()
        }
        return nil
    }

    private func alternatingFill(_ row: ContentKit.TableRow, layout: Layout) -> Color {
        guard usesZebra else { return .clear }
        let rows = layout.block.rows ?? []
        guard let index = rows.firstIndex(where: { $0 == row }) else { return .clear }
        return index % 2 == 1 ? theme.zebra : .clear
    }

    private func cellTextAlignment(_ cell: TableCell) -> TextAlignment {
        switch cell.al ?? block.ta {
        case "c": .center
        case "r": .trailing
        default: .leading
        }
    }

    private func cellFrameAlignment(_ cell: TableCell) -> Alignment {
        switch cell.al ?? block.ta {
        case "c": .top
        case "r": .topTrailing
        default: .topLeading
        }
    }

    /// 隔行底色：源 HTML 没有，按网页版（WebHelp 模板）的观感加。
    ///
    /// 源页自己给了行/单元格底色的不动——两套配色叠在一起会脏。
    private var usesZebra: Bool {
        if ancestors.contains("stat-block") { return false }
        let rows = block.rows ?? []
        let custom = rows.contains { row in
            row.bg != nil || row.cells.contains { $0.bg != nil }
        }
        return !custom
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
            // 单元格里的嵌套块也要跟随单元格对齐，否则同一格里
            // 一段居中、一段贴左，看着像错位
            BlockView(
                block: inner, ancestors: ancestors, highlight: nil, availableWidth: cellWidth,
                inheritedAlignment: cell.al ?? block.ta
            )
        } else if inner.runsOrEmpty.contains(where: { $0.img != nil }) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Self.pieces(inner.runsOrEmpty).enumerated()), id: \.offset) {
                    _, piece in
                    switch piece {
                    case .text(let runs):
                        Text(
                            AttributedText.make(
                                runs, size: layout.fontSize, bold: cell.header == true,
                                theme: theme, mentionLevel: mentionLevel)
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
                    theme: theme, mentionLevel: mentionLevel)
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

    private func cellView(_ cell: TableCell, column: Int, span: Int, layout: Layout) -> some View {
        let span = max(1, span)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                cellBlock(
                    inner, cell: cell, layout: layout,
                    cellWidth: width(at: column, span: span, layout: layout))
            }
        }
        .multilineTextAlignment(cellTextAlignment(cell))
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(
            width: width(at: column, span: span, layout: layout),
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
