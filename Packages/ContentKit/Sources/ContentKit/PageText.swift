import Foundation

/// 把 block 序列拆成"叶子段落"，并记住每段属于哪个顶层 block。
///
/// **必须与 `Tools/content/pack.py::page_text` 完全一致**：搜索的候选校验靠它，
/// 两边差一点就会搜出错结果。跨语言自检见 `ContentDatabase.verifyTextDigest()`。
public enum PageText {

    /// 一个叶子段落：文本 + 它所属的顶层 block 序号（用于跳转定位）。
    public struct Leaf: Sendable {
        public let blockIndex: Int
        public let text: String
    }

    /// 必须复刻 Python `str.strip()` 的空白集合。
    ///
    /// Foundation 的 `whitespacesAndNewlines` **不含** U+001C–U+001F 和 U+0085，
    /// 而 Python 的 `str.isspace()` 认为它们都是空白。上游表格里确实有
    /// 只用 `\x1f` 填充的分隔单元格，差这一个集合就会出现差异。
    static let pythonWhitespace: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{1C}\u{1D}\u{1E}\u{1F}\u{85}")
        return set
    }()

    public static func of(_ blocks: [Block], separator: String = "\n") -> String {
        nonEmptyLeaves(blocks).map(\.text).joined(separator: separator)
    }

    /// 过滤掉只有空白的叶子——与 Python 的 `if p.strip()` 对应。
    public static func nonEmptyLeaves(_ blocks: [Block]) -> [Leaf] {
        leaves(blocks).filter { !$0.text.trimmingCharacters(in: pythonWhitespace).isEmpty }
    }

    public static func leaves(_ blocks: [Block]) -> [Leaf] {
        var out: [Leaf] = []
        for (index, block) in blocks.enumerated() {
            append(block, topIndex: index, into: &out)
        }
        return out
    }

    /// 某个顶层 block 的正文起始偏移（用于保存阅读位置）。
    public static func offset(ofBlock index: Int, in blocks: [Block]) -> Int? {
        var cursor = 0
        for leaf in nonEmptyLeaves(blocks) {
            if leaf.blockIndex == index { return cursor }
            cursor += leaf.text.count + 1
        }
        return nil
    }

    /// 取某个偏移附近的一段文字，作为位置失效时的兜底线索。
    public static func snippet(at offset: Int, in blocks: [Block], length: Int = 20) -> String {
        let text = of(blocks)
        guard !text.isEmpty else { return "" }
        let clamped = min(max(0, offset), text.count)
        let start = text.index(text.startIndex, offsetBy: clamped)
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        return text[start..<end].replacingOccurrences(of: "\n", with: " ")
    }

    /// 把整页正文里的字符偏移映射到顶层 block 序号。找不到时返回 nil。
    public static func blockIndex(forOffset offset: Int, in blocks: [Block]) -> Int? {
        var cursor = 0
        for leaf in nonEmptyLeaves(blocks) {
            let end = cursor + leaf.text.count
            if offset < end { return leaf.blockIndex }
            cursor = end + 1  // 分隔符 "\n"
        }
        return nil
    }

    private static func append(_ block: Block, topIndex: Int, into out: inout [Leaf]) {
        switch block.type {
        case "h", "p", "dt", "dd":
            out.append(
                Leaf(
                    blockIndex: topIndex,
                    text: block.runsOrEmpty.compactMap(\.t).joined()))
        case "pre":
            out.append(Leaf(blockIndex: topIndex, text: block.text ?? ""))
        case "div", "quote":
            for child in block.blocksOrEmpty {
                append(child, topIndex: topIndex, into: &out)
            }
        case "list":
            for item in block.items ?? [] {
                out.append(
                    Leaf(
                        blockIndex: topIndex,
                        text: item.runs.compactMap(\.t).joined()))
                for child in item.blocks {
                    append(child, topIndex: topIndex, into: &out)
                }
            }
        case "table":
            for row in block.rows ?? [] {
                for cell in row.cells {
                    for child in cell.blocks {
                        append(child, topIndex: topIndex, into: &out)
                    }
                }
            }
        default:
            break
        }
    }
}
