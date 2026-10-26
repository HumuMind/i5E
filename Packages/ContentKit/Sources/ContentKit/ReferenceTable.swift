import Foundation

public struct ReferenceCell: Sendable, Hashable {
    public var text: String
    /// 单元格里若只有一个链接，保留它的 href，卡片上点标题即可跳转。
    public var link: String?

    public init(text: String, link: String? = nil) {
        self.text = text
        self.link = link
    }
}

/// 从页面里抽出"速查表"。
///
/// 判据：页面里行数最多的一张表，且至少 `minimumRows` 行。
/// 达到这个量级才值得换一套展示方式，普通的小表格仍然留在文档流里。
public struct ReferenceTable: Sendable {
    public var title: String
    public var headers: [String]
    public var rows: [[ReferenceCell]]

    public init(title: String, headers: [String], rows: [[ReferenceCell]]) {
        self.title = title
        self.headers = headers
        self.rows = rows
    }

    public var columnCount: Int {
        rows.map(\.count).max() ?? headers.count
    }

    /// 某一列有多少种不同取值。恒定列（只有一种取值）在卡片上没有信息量。
    public func distinctCount(column: Int) -> Int {
        var seen = Set<String>()
        for row in rows where column < row.count {
            seen.insert(row[column].text.trimmingCharacters(in: .whitespaces))
        }
        return seen.count
    }

    /// 某一列的去重取值，用来生成筛选条件；取值太多（如名称列）返回空。
    public func facets(column: Int, limit: Int = 14) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows where column < row.count {
            let value = row[column].text.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.count <= 16, !seen.contains(value) else { continue }
            seen.insert(value)
            ordered.append(value)
            if ordered.count > limit { return [] }
        }
        return ordered.count > 1 ? ordered.sorted() : []
    }
}

public enum ReferenceTableExtractor {

    public static let minimumRows = 50

    public static func extract(from page: Page) -> ReferenceTable? {
        var best: (table: Block, rows: Int)?
        for block in page.blocks where block.type == "table" {
            let count = block.rows?.count ?? 0
            if count > (best?.rows ?? 0) {
                best = (block, count)
            }
        }
        guard let best, best.rows >= minimumRows else { return nil }

        let rawRows = (best.table.rows ?? []).map { row in
            row.cells.map(cellText)
        }
        guard rawRows.count > 1 else { return nil }

        // 表头：第一行没有链接、且每格都短，就当作表头
        let first = rawRows[0]
        let looksLikeHeader =
            first.allSatisfy { $0.link == nil && $0.text.count <= 12 && !$0.text.isEmpty }
            && rawRows.dropFirst().contains { $0.first?.link != nil }

        let headers: [String]
        let body: [[ReferenceCell]]
        if looksLikeHeader {
            headers = first.map { $0.text }
            body = Array(rawRows.dropFirst())
        } else {
            headers = []
            body = rawRows
        }

        let rows = body.filter { row in row.contains { !$0.text.isEmpty } }
        guard rows.count >= minimumRows else { return nil }
        return ReferenceTable(title: page.title, headers: headers, rows: rows)
    }

    private static func cellText(_ cell: TableCell) -> ReferenceCell {
        var parts: [String] = []
        var link: String?
        func walk(_ blocks: [Block]) {
            for block in blocks {
                if block.type == "p" || block.type == "h" {
                    for run in block.runsOrEmpty {
                        if let text = run.t { parts.append(text) }
                        if link == nil, let href = run.href { link = href }
                    }
                } else if block.type == "table" {
                    for row in block.rows ?? [] {
                        for inner in row.cells { walk(inner.blocks) }
                    }
                } else {
                    walk(block.blocksOrEmpty)
                }
            }
        }
        walk(cell.blocks)
        let text = parts.joined()
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ReferenceCell(text: text, link: link)
    }
}
