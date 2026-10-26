import CoreGraphics
import Foundation

/// 源页用 class 表达的样式，取自 `DND5e_chm/stat-block.css`。
///
/// 只收录**结构性**的类（容器、数据块、表格单元格），不收录排版微调。
/// 这些类覆盖约 900 个页面，是"一类现象"而不是个别页面。
public enum ClassStyle {

    public struct Container: Sendable, Equatable {
        public var background: String
        public var border: String
        public var borderWidth: CGFloat
        public var paddingTop: CGFloat
        public var paddingHorizontal: CGFloat
        public var maxWidth: CGFloat?
        /// 左右各留多少比例的外边距（源页 `div.center` 是 8%）
        public var marginFraction: CGFloat
        /// 只画上边框（如 `div.HT`）
        public var topBorderOnly: Bool
    }

    public static func container(_ classes: [String]) -> Container? {
        if classes.contains("stat-block") {
            return Container(
                background: "#f8f8f6", border: "#808080", borderWidth: 3,
                paddingTop: 15, paddingHorizontal: 15, maxWidth: 560,
                marginFraction: 0, topBorderOnly: false)
        }
        if classes.contains("little-paper") {
            return Container(
                background: "#faf0eb", border: "#9e6859", borderWidth: 3,
                paddingTop: 15, paddingHorizontal: 15, maxWidth: 560,
                marginFraction: 0, topBorderOnly: false)
        }
        if classes.contains("HT") {
            return Container(
                background: "#f0e9da", border: "#d1bc90", borderWidth: 3,
                paddingTop: 5, paddingHorizontal: 5, maxWidth: 580,
                marginFraction: 0, topBorderOnly: true)
        }
        if classes.contains("center") {
            // div.center：带边框的强调框，左右各留 8% 外边距
            return Container(
                background: "#ebd6c1", border: "#656565", borderWidth: 2,
                paddingTop: 10, paddingHorizontal: 50, maxWidth: nil,
                marginFraction: 0.08, topBorderOnly: false)
        }
        return nil
    }

    /// 单元格底色（`td.c1` 等），用于属性表这类斑马纹。
    public static func cellBackground(_ classes: [String]?) -> String? {
        guard let classes else { return nil }
        for name in ["c1", "c2", "c3", "c4"] where classes.contains(name) {
            switch name {
            case "c1": return "#e9e3d6"
            case "c2": return "#d8d0c9"
            case "c3": return "#d2d6ce"
            default: return "#cbc6c6"
            }
        }
        return nil
    }

    /// `div.sub-line`：怪物数据块里那行灰斜体的"中型野兽，无阵营"。
    public static func isSubLine(_ classes: [String]?) -> Bool {
        classes?.contains("sub-line") == true
    }

    /// `table.basic` / `table.center` / `table.part`：无边框表格。
    public static func isBorderlessTable(_ classes: [String]?) -> Bool {
        guard let classes else { return false }
        return classes.contains("basic") || classes.contains("center") || classes.contains("part")
    }

    /// 数据块内部的标题（h5 / h6）在源页里是暗红加粗带下划线。
    public static func isStatBlockHeading(ancestors: Set<String>) -> Bool {
        ancestors.contains("stat-block")
    }
}
