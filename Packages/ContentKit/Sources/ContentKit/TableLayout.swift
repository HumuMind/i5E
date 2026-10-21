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
