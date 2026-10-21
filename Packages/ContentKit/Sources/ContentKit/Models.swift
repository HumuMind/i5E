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

    public init(
        t: String? = nil, img: String? = nil, alt: String? = nil,
        b: Int? = nil, i: Int? = nil, u: Int? = nil, s: Int? = nil,
        sup: Int? = nil, sub: Int? = nil, code: Int? = nil, href: String? = nil,
        c: String? = nil, sz: Double? = nil, fa: String? = nil
    ) {
        self.t = t; self.img = img; self.alt = alt
        self.b = b; self.i = i; self.u = u; self.s = s
        self.sup = sup; self.sub = sub; self.code = code; self.href = href
        self.c = c; self.sz = sz; self.fa = fa
    }
}

public struct ListItem: Decodable, Sendable, Hashable {
    public var runs: [Run]
    public var blocks: [Block]
}

public struct TableCell: Decodable, Sendable, Hashable {
    public var blocks: [Block]
    public var colspan: Int?
    public var rowspan: Int?
    public var header: Bool?
    public var bg: String?
    public var cls: [String]?
}

public struct TableRow: Decodable, Sendable, Hashable {
    public var cells: [TableCell]
    public var bg: String?
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

    public var runsOrEmpty: [Run] { runs ?? [] }
    public var blocksOrEmpty: [Block] { blocks ?? [] }

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

    public init(id: Int64, path: String, title: String, blocks: [Block]) {
        self.id = id; self.path = path; self.title = title; self.blocks = blocks
    }
}

public struct SearchHit: Sendable, Identifiable, Hashable {
    public var id: String { "\(pageID)" }
    public var pageID: Int64
    public var path: String
    public var title: String
    public var snippet: String

    public init(pageID: Int64, path: String, title: String, snippet: String) {
        self.pageID = pageID; self.path = path; self.title = title; self.snippet = snippet
    }
}
