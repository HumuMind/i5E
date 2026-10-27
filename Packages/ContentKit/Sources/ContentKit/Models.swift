import Foundation

/// 内容库的数据模型，与 Tools/content 产出的 JSON 一一对应。
/// 字段名短是刻意的：block 数量大，全名会让内容包明显变大。

public struct Run: Decodable, Sendable, Hashable {
    public var t: String?  // 文本
    public var img: String?  // 图片路径
    public var alt: String?
    public var b: Int?  // 粗体
    public var i: Int?  // 斜体
    public var u: Int?  // 下划线
    public var s: Int?  // 删除线
    public var sup: Int?
    public var sub: Int?
    public var code: Int?
    public var href: String?
    public var c: String?  // 颜色 #rrggbb
    public var sz: Double?  // 字号（pt，源页值）
    public var fa: String?  // 字体族 song/hei/kai/fang/sans/times/mono
    public var w: Int?  // 图片宽度（源页 px）
    public var h: Int?  // 图片高度（源页 px）
    public var align: String?  // 图片浮动方向 left/right

    public init(
        t: String? = nil, img: String? = nil, alt: String? = nil,
        b: Int? = nil, i: Int? = nil, u: Int? = nil, s: Int? = nil,
        sup: Int? = nil, sub: Int? = nil, code: Int? = nil, href: String? = nil,
        c: String? = nil, sz: Double? = nil, fa: String? = nil,
        w: Int? = nil, h: Int? = nil, align: String? = nil
    ) {
        self.t = t; self.img = img; self.alt = alt
        self.b = b; self.i = i; self.u = u; self.s = s
        self.sup = sup; self.sub = sub; self.code = code; self.href = href
        self.c = c; self.sz = sz; self.fa = fa
        self.w = w; self.h = h; self.align = align
    }
}

public struct ListItem: Decodable, Sendable, Hashable {
    public var runs: [Run]
    public var blocks: [Block]
}

public struct TableCell: Decodable, Sendable, Hashable {
    public var blocks: [Block]
    /// 单元格对齐：c 居中 / r 右对齐 / j 两端
    public var al: String?
    public var colspan: Int?
    public var rowspan: Int?
    public var header: Bool?
    public var bg: String?
    public var cls: [String]?

    /// 单元格纯文本，用于估宽。
    public var plainText: String { blocks.map(\.deepPlainText).joined() }

    /// 单元格里是否有图片（排版表格里常见"文字 | 插图"两栏）。
    public var hasImage: Bool {
        blocks.contains { block in
            block.runsOrEmpty.contains { $0.img != nil }
                || block.blocksOrEmpty.contains { $0.runsOrEmpty.contains { $0.img != nil } }
        }
    }
}

public struct TableRow: Decodable, Sendable, Hashable {
    public var cells: [TableCell]
    public var bg: String?
}

/// 页面内联 `<style>` 解析出的标签级样式（见 Tools/content/inline_css.py）。
public struct BlockStyle: Decodable, Sendable, Hashable {
    public var c: String?
    public var b: Int?
    /// 标题下划线颜色；"1" 表示有下划线但没指定颜色
    public var bd: String?
    /// 标题对齐：c 居中 / r 右对齐 / j 两端
    public var al: String?
}

public struct Block: Decodable, Sendable, Hashable {
    public var type: String
    public var level: Int?
    public var id: String?
    public var runs: [Run]?
    public var items: [ListItem]?
    public var rows: [TableRow]?
    public var blocks: [Block]?
    public var text: String?
    public var ordered: Bool?
    public var caption: String?
    public var cls: [String]?
    public var anchors: [String]?
    public var al: String?
    public var ind: Double?
    public var style: BlockStyle?
    /// 表格显式宽度（源页 px）与百分比宽度
    public var w: Int?
    public var wp: Int?
    /// 源页是否给这张表画了边框（没写 border 属性、页面 CSS 也没加时默认无边框）
    public var bd: Int?
    /// 表格级 text-align，作用到所有单元格
    public var ta: String?

    public var runsOrEmpty: [Run] { runs ?? [] }
    public var blocksOrEmpty: [Block] { blocks ?? [] }

    /// 递归拼接本块及嵌套块的文本，用于表格估宽。
    public var deepPlainText: String {
        var parts: [String] = []
        if !plainText.isEmpty { parts.append(plainText) }
        for child in blocksOrEmpty { parts.append(child.deepPlainText) }
        for item in items ?? [] {
            parts.append(item.runs.compactMap(\.t).joined())
            for child in item.blocks { parts.append(child.deepPlainText) }
        }
        for row in rows ?? [] {
            for cell in row.cells { parts.append(cell.plainText) }
        }
        return parts.joined()
    }

    /// 块级纯文本，顺序与 Tools/content/model.py 的 blocks_text 一致。
    public var plainText: String {
        switch type {
        case "h", "p", "dt", "dd":
            return runsOrEmpty.compactMap(\.t).joined()
        case "pre":
            return text ?? ""
        default:
            return ""
        }
    }
}

public struct TOCNode: Decodable, Sendable, Hashable, Identifiable {
    public var t: String  // 标题
    public var u: String?  // 页面路径
    public var c: [TOCNode]  // 子节点
    public var id: String { (u ?? "") + "|" + t + "|" + String(c.count) }
}

public struct TOC: Decodable, Sendable {
    public var title: String
    public var nodes: [TOCNode]
}

public struct Page: Sendable {
    public var id: Int64
    public var path: String
    public var title: String
    public var blocks: [Block]
    /// 是否引用了上游的 `style.css`。标题的默认颜色来自那份样式表，
    /// 没引用它的页面（全库 4,244 页）标题在浏览器里是黑色。
    public var usesStyleSheet: Bool

    public init(
        id: Int64, path: String, title: String, blocks: [Block],
        usesStyleSheet: Bool = true
    ) {
        self.id = id; self.path = path; self.title = title; self.blocks = blocks
        self.usesStyleSheet = usesStyleSheet
    }
}

public struct SearchHit: Sendable, Identifiable, Hashable {
    public var id: String { "\(pageID)" }
    public var pageID: Int64
    public var path: String
    public var title: String
    public var snippet: String
    /// 首处命中所在的顶层 block 序号，用于跳转定位。
    public var blockIndex: Int

    public init(pageID: Int64, path: String, title: String, snippet: String, blockIndex: Int) {
        self.pageID = pageID
        self.path = path
        self.title = title
        self.snippet = snippet
        self.blockIndex = blockIndex
    }
}

extension Page {
    /// 找到锚点所在的**顶层** block 序号。
    ///
    /// 锚点可能挂在表格单元格、列表项或容器里的块上（全库约 765 个），
    /// 只扫顶层会漏掉它们，链接就落不到目标位置。这里递归找，
    /// 但返回的是它所属的顶层块——滚动只能定位到顶层块。
    public func blockIndex(forAnchor anchor: String) -> Int? {
        for (index, block) in blocks.enumerated() where Self.contains(anchor: anchor, in: block) {
            return index
        }
        return nil
    }

    private static func contains(anchor: String, in block: Block) -> Bool {
        if block.id == anchor || block.anchors?.contains(anchor) == true { return true }
        for child in block.blocksOrEmpty where contains(anchor: anchor, in: child) { return true }
        for item in block.items ?? [] {
            for child in item.blocks where contains(anchor: anchor, in: child) { return true }
        }
        for row in block.rows ?? [] {
            for cell in row.cells {
                for child in cell.blocks where contains(anchor: anchor, in: child) { return true }
            }
        }
        return false
    }

    /// 从 `URL` 解析路径与锚点。
    ///
    /// 注意：含中文的链接经 `URL(string:)` 之后，`relativeString` 是百分号编码的，
    /// 直接拿去查库会查不到。这里用 `url.path`（已解码）而不是字符串拆分。
    public static func splitURL(_ url: URL) -> (path: String?, anchor: String?) {
        let decoded = url.path.removingPercentEncoding ?? url.path
        return (decoded.isEmpty ? nil : decoded, url.fragment)
    }

    /// 解析链接里的路径与锚点。
    public static func splitLink(_ href: String) -> (path: String?, anchor: String?) {
        if href.hasPrefix("#") { return (nil, String(href.dropFirst())) }
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.first.map(String.init)
        let anchor = parts.count > 1 ? String(parts[1]) : nil
        return (path, anchor)
    }
}
