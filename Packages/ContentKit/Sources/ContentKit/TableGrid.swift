import Foundation

/// 表格网格：把 `colspan` / `rowspan` 展开成"每个格子在网格里的位置"。
///
/// `Block` 每行只按顺序存格子、没有列号，所以带 `rowspan` 时后续行的格子会被
/// 顶到上一行的占位上（魔战士/法师这些职业法术表的第二行表头整排左移）。
/// 这里按 HTML 表格的规则走一遍：被上方合并格占住的列跳过，每行都得到明确的起始列。
///
/// 只做横向定位：纵向合并的格子在首行渲染内容，被覆盖的行留空（见 0015）。
public struct TableGrid {

    public struct Placement {
        public var cell: TableCell
        public var row: Int
        public var column: Int
        public var colspan: Int
        public var rowspan: Int
    }

    /// 渲染一行需要的槽位：格子，或空洞（被上方合并格占住、行尾缺列）。
    public enum Slot {
        case cell(Placement)
        case hole(column: Int, colspan: Int)
    }

    /// 网格总列数（含只有 rowspan 覆盖、本行没有新格子的列）。
    public let columnCount: Int
    /// 每行"起点在这一行"的格子，按列升序。
    public let rows: [[Placement]]
    /// 全部格子，按行优先。
    public let placements: [Placement]

    public init(_ block: Block) {
        var pending: [Int] = []  // 每列还被上方合并格占住几行（含当前行）
        var rows: [[Placement]] = []
        var placements: [Placement] = []
        var width = 0

        for (rowIndex, row) in (block.rows ?? []).enumerated() {
            var column = 0
            var placed: [Placement] = []
            for cell in row.cells {
                while column < pending.count, pending[column] > 0 {
                    column += 1
                }
                let colspan = max(1, cell.colspan ?? 1)
                let rowspan = max(1, cell.rowspan ?? 1)
                if column + colspan > pending.count {
                    pending.append(
                        contentsOf: Array(repeating: 0, count: column + colspan - pending.count))
                }
                for offset in 0..<colspan {
                    pending[column + offset] = rowspan
                }
                width = max(width, column + colspan)
                let placement = Placement(
                    cell: cell, row: rowIndex, column: column, colspan: colspan, rowspan: rowspan)
                placed.append(placement)
                placements.append(placement)
                column += colspan
            }
            for index in pending.indices where pending[index] > 0 {
                pending[index] -= 1
            }
            rows.append(placed)
        }

        self.columnCount = width
        self.rows = rows
        self.placements = placements
    }

    /// 把某一行摊成连续的槽位，横向正好铺满 `columnCount` 列。
    public func slots(in row: Int) -> [Slot] {
        guard rows.indices.contains(row) else { return [] }
        var slots: [Slot] = []
        var cursor = 0
        for placement in rows[row] {
            if placement.column > cursor {
                slots.append(.hole(column: cursor, colspan: placement.column - cursor))
            }
            slots.append(.cell(placement))
            cursor = placement.column + placement.colspan
        }
        if cursor < columnCount {
            slots.append(.hole(column: cursor, colspan: columnCount - cursor))
        }
        return slots
    }
}
