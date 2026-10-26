import CoreGraphics
import Foundation

/// 表格列宽计算。
///
/// 规则来自 [0015](../../../../Docs/decisions/0015-table-layout.md)：
/// 按内容估宽、自然宽度不铺满、低于下限就换行、不支持 rowspan。
public enum TableLayoutCalculator {

    /// 单列内容宽度的上限（单位：半角字符宽）。超过就换行，不再撑宽。
    public static let maxUnits: Double = 24
    /// 单列宽度下限（3 个汉字宽）。
    public static let minUnits: Double = 6
    /// 单元格左右内边距之和。
    public static let horizontalPadding: CGFloat = 12

    public static func columnCount(_ block: Block) -> Int {
        (block.rows ?? []).map { $0.cells.reduce(0) { $0 + max(1, $1.colspan ?? 1) } }.max() ?? 0
    }

    /// 每列需要多少个"半角字符宽"。
    public static func columnUnits(_ block: Block) -> [Double] {
        let count = columnCount(block)
        guard count > 0 else { return [] }
        var units = Array(repeating: 0.0, count: count)

        for row in block.rows ?? [] {
            var column = 0
            for cell in row.cells {
                let span = max(1, cell.colspan ?? 1)
                let width = min(maxUnits, displayUnits(cell.plainText))
                let share = width / Double(span)
                for offset in 0..<span where column + offset < count {
                    units[column + offset] = max(units[column + offset], share)
                }
                column += span
            }
        }
        return units.map { max(minUnits, $0) }
    }

    /// 去掉整列都没有文字的列。
    ///
    /// 源页里常见两种：`<td width=40%>` 占位导致的空列，以及属性表里
    /// `<td WIDTH=5px>` 这种纯间隔列。它们没有任何文字，却会被算进列宽，
    /// 把真正的内容挤窄。这里把表格规范化：展开 colspan → 去掉空列 → 重新合并。
    public static func normalize(_ block: Block) -> Block {
        let rows = block.rows ?? []
        guard !rows.isEmpty else { return block }

        // 1) 展开成网格
        var grid: [[TableCell?]] = []
        var width = 0
        for row in rows {
            var cells: [TableCell?] = []
            for cell in row.cells {
                let span = max(1, cell.colspan ?? 1)
                cells.append(cell)
                for _ in 1..<span { cells.append(nil) }
            }
            width = max(width, cells.count)
            grid.append(cells)
        }

        // 2) 哪些列有内容
        var keep = Array(repeating: false, count: width)
        for cells in grid {
            for (index, cell) in cells.enumerated() where index < width {
                guard let cell, !cell.plainText.isEmpty else { continue }
                keep[index] = true
            }
        }
        guard keep.contains(false), keep.contains(true) else { return block }

        // 3) 重新合并：相邻且属于同一个原始单元格的保留列并成一格
        var rebuilt: [TableRow] = []
        for (rowIndex, cells) in grid.enumerated() {
            var newCells: [TableCell] = []
            var cursor = 0
            while cursor < width {
                guard cursor < cells.count, let origin = cells[cursor] else {
                    cursor += 1
                    continue
                }
                var span = 0
                var probe = cursor
                while probe < width, probe == cursor || cells[probe] == nil {
                    if keep[probe] { span += 1 }
                    probe += 1
                }
                if span > 0 {
                    var cell = origin
                    cell.colspan = span
                    newCells.append(cell)
                }
                cursor = probe
            }
            rebuilt.append(TableRow(cells: newCells, bg: rows[rowIndex].bg))
        }
        var result = block
        result.rows = rebuilt
        return result
    }

    /// 计算实际列宽（pt）。总和不超过 `available`；内容窄时保持自然宽度。
    public static func widths(_ block: Block, fontSize: CGFloat, available: CGFloat) -> [CGFloat] {
        let units = columnUnits(block)
        guard !units.isEmpty else { return [] }

        let natural = units.map { CGFloat($0) * fontSize / 2 + horizontalPadding }
        let total = natural.reduce(0, +)
        guard total > available, available > 0 else { return natural }

        let floor = CGFloat(minUnits) * fontSize / 2 + horizontalPadding
        let scale = available / total
        var scaled = natural.map { max(floor, $0 * scale) }

        let sum = scaled.reduce(0, +)
        if sum > available {
            scaled = scaled.map { $0 * available / sum }
        }
        return scaled
    }

    /// 近似计算显示宽度：CJK 与全角符号算 2，其余算 1。
    public static func displayUnits(_ text: String) -> Double {
        var units = 0.0
        for character in text {
            units += isWide(character) ? 2 : 1
        }
        return units
    }

    private static func isWide(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x1100...0x115F).contains(value)
            || value == 0x2329 || value == 0x232A
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE30...0xFE6F).contains(value)
            || (0xFF00...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x20000...0x3FFFD).contains(value)
    }
}
