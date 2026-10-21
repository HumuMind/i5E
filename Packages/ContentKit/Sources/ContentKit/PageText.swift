import Foundation

/// 把 block 序列拼成整页正文。
///
/// **必须与 `Tools/content/pack.py::page_text` 完全一致**：搜索的候选校验靠它，
/// 两边差一点就会搜出错结果。跨语言自检见 `ContentDatabase.verifyTextDigest()`。
public enum PageText {

    /// 必须复刻 Python `str.strip()` 的空白集合。
    ///
    /// Swift 与 Python 在这里不一致：Foundation 的 `whitespacesAndNewlines` **不含**
    /// U+001C–U+001F 和 U+0085，而 Python 的 `str.isspace()` 认为它们都是空白。
    /// 上游表格里确实有只用 `\x1f` 填充的分隔单元格，差这一个集合就会出现差异。
    private static let pythonWhitespace: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{1C}\u{1D}\u{1E}\u{1F}\u{85}")
        return set
    }()

    public static func of(_ blocks: [Block], separator: String = "\n") -> String {
        var parts: [String] = []
        walk(blocks, into: &parts)
        return
            parts
            .filter { !$0.trimmingCharacters(in: pythonWhitespace).isEmpty }
            .joined(separator: separator)
    }

    private static func walk(_ blocks: [Block], into parts: inout [String]) {
        for block in blocks {
            switch block.type {
            case "h", "p", "dt", "dd":
                parts.append(block.runsOrEmpty.compactMap(\.t).joined())
            case "pre":
                parts.append(block.text ?? "")
            case "div", "quote":
                walk(block.blocksOrEmpty, into: &parts)
            case "list":
                for item in block.items ?? [] {
                    parts.append(item.runs.compactMap(\.t).joined())
                    walk(item.blocks, into: &parts)
                }
            case "table":
                for row in block.rows ?? [] {
                    for cell in row.cells {
                        walk(cell.blocks, into: &parts)
                    }
                }
            default:
                continue
            }
        }
    }
}
