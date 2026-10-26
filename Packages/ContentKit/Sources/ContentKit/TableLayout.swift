import CoreGraphics
import CoreText
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

    /// 每列**不设上限**的内容宽度（单位：半角字符宽）。
    /// 用于在表格还没占满可用宽度时，把多余空间分给需要换行的列。
    public static func contentUnits(_ block: Block) -> [Double] {
        let count = columnCount(block)
        guard count > 0 else { return [] }
        var units = Array(repeating: 0.0, count: count)
        for row in block.rows ?? [] {
            var column = 0
            for cell in row.cells {
                let span = max(1, cell.colspan ?? 1)
                let width = displayUnits(cell.plainText)
                let share = width / Double(span)
                for offset in 0..<span where column + offset < count {
                    units[column + offset] = max(units[column + offset], share)
                }
                column += span
            }
        }
        return units
    }

    /// 每列内容的**实测**单行宽度（pt），用于"有空间就放宽"的上限。
    ///
    /// 用估算值当上限会把 `伊米希Imix, 卡普斯Kossuth, 扎曼·鲁尔Zaaman Rul`
    /// 这类中英混排压窄——拉丁字母实际比"半个字宽"要宽。
    public static func measuredContentWidths(_ block: Block, fontSize: CGFloat) -> [CGFloat] {
        let count = columnCount(block)
        guard count > 0 else { return [] }
        var widths = Array(repeating: CGFloat(0), count: count)
        for row in (block.rows ?? []).prefix(60) {
            var column = 0
            for cell in row.cells {
                let span = max(1, cell.colspan ?? 1)
                if span == 1, column < count {
                    let width = lineWidth(cell.plainText, fontSize: fontSize)
                    widths[column] = max(widths[column], width)
                }
                column += span
            }
        }
        return widths.map { $0 + horizontalPadding }
    }

    /// 单行渲染宽度。
    private static func lineWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 每列"不能被断开的最短宽度"（pt）。
    ///
    /// 拉丁词与数字串（`PHB24`、`1d6+2`）不能从中间折行，列宽再紧也得容下它们。
    /// 用 CoreText 实测而不是按字符数估算——拉丁字母比"半个字宽"要宽，
    /// 估算会让 `PHB24` 被折成两行。
    public static func minimumWidths(_ block: Block, fontSize: CGFloat) -> [CGFloat] {
        let count = columnCount(block)
        guard count > 0 else { return [] }
        var minimum = Array(repeating: CGFloat(0), count: count)

        for row in block.rows ?? [] {
            var column = 0
            for cell in row.cells {
                let span = max(1, cell.colspan ?? 1)
                if span == 1, column < count {
                    let width = longestTokenWidth(cell.plainText, fontSize: fontSize)
                    minimum[column] = max(minimum[column], width)
                }
                column += span
            }
        }
        return minimum.map { $0 + horizontalPadding }
    }

    /// 最长的不可断片段（连续的非空白 ASCII）的渲染宽度。
    private static func longestTokenWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        var longest = ""
        var current = ""
        for character in text {
            if character.isASCII, !character.isWhitespace {
                current.append(character)
                if current.count > longest.count { longest = current }
            } else {
                current = ""
            }
        }
        guard !longest.isEmpty else { return 0 }
        let font =
            CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: longest, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 文本里最长的不可断片段：连续的数字/拉丁字符/小数点/加号。
    /// 单位与 `displayUnits` 一致：半角字符记 1，全角记 2。
    private static func longestToken(_ text: String) -> Double {
        var best = 0.0
        var current = 0.0
        for character in text {
            if character.isASCII, !character.isWhitespace {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    /// 计算实际列宽（pt）。总和不超过 `available`；内容窄时保持自然宽度。
    public static func widths(_ block: Block, fontSize: CGFloat, available: CGFloat) -> [CGFloat] {
        let units = columnUnits(block)
        guard !units.isEmpty else { return [] }

        let minimums = minimumWidths(block, fontSize: fontSize)
        // 估算宽度不能小于"不可断词"的实测宽度，否则 PHB24 会被折成两行
        let natural = units.enumerated().map { index, unit in
            let estimated = CGFloat(unit) * fontSize / 2 + horizontalPadding
            let floor = index < minimums.count ? minimums[index] : 0
            return max(estimated, floor)
        }
        let total = natural.reduce(0, +)
        guard available > 0 else { return natural }
        if total < available {
            // 还没占满可用宽度：把多余空间分给"内容比当前列宽更长"的列，
            // 避免明明有地方却把长条目折成两三行。
            let content = contentUnits(block)
            let measured = measuredContentWidths(block, fontSize: fontSize)
            let extra = zip(content, units).map { max(0, $0 - $1) }
            let totalExtra = extra.reduce(0, +)
            guard totalExtra > 0 else { return natural }
            let spare = available - total
            return natural.enumerated().map { index, width in
                guard index < content.count else { return width }
                let estimated = CGFloat(content[index]) * fontSize / 2 + horizontalPadding
                // 上限取实测宽度：估算偏窄会把还能放下的一行挤成两行
                let measuredCap = index < measured.count ? measured[index] : 0
                // 也不能低于"不可断词"的实测下限，否则 d6 会被压回两行
                let floor = index < minimums.count ? minimums[index] : 0
                let cap = max(max(estimated, measuredCap), floor)
                let share = spare * extra[index] / totalExtra
                return min(cap, max(floor, width + share))
            }
        }

        let scale = available / total
        var scaled = natural.enumerated().map { index, width in
            let floor = index < minimums.count ? minimums[index] : 0
            return max(floor, width * scale)
        }

        // 第一轮已经把过宽的列压到下限；如果总和仍超出，只能从"高于下限的部分"里扣，
        // 否则会把 d6 这种短词再压回换行。
        let sum = scaled.reduce(0, +)
        if sum > available {
            let floors = scaled.indices.map { index in
                index < minimums.count ? minimums[index] : 0
            }
            let slack = scaled.indices.map { max(0, scaled[$0] - floors[$0]) }
            let totalSlack = slack.reduce(0, +)
            if totalSlack > 0 {
                let excess = sum - available
                scaled = scaled.indices.map { index in
                    let cut = excess * slack[index] / totalSlack
                    return max(floors[index], scaled[index] - cut)
                }
            }
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
