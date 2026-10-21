import Foundation

/// 把扁平的上游目录切成章节。
///
/// 上游用它自己的分隔节点（`——核心规则——` 这类，无子节点、标题带破折号）分组，
/// 所以不需要重新组织内容，只要识别分隔符。
public struct TOCSection: Sendable, Identifiable, Hashable {
    public var title: String
    public var nodes: [TOCNode]
    /// 前置固定入口（分隔符之前的内容）与末尾的杂项标记。
    public var isPinned: Bool

    public var id: String { (isPinned ? "pin:" : "sec:") + title }

    public init(title: String, nodes: [TOCNode], isPinned: Bool = false) {
        self.title = title
        self.nodes = nodes
        self.isPinned = isPinned
    }
}

public enum TOCSectionBuilder {

    /// 这些顶层节点放到最后，不参与正常章节。
    public static let trailingTitles: Set<String> = ["补遗（未归类）", "未收录于目录"]

    public static func isSeparator(_ node: TOCNode) -> Bool {
        guard node.c.isEmpty else { return false }
        let title = node.t.trimmingCharacters(in: .whitespaces)
        guard title.count >= 4 else { return false }
        return title.allSatisfy { "—-─".contains($0) || title.contains("——") }
    }

    public static func build(from nodes: [TOCNode]) -> [TOCSection] {
        var pinned: [TOCNode] = []
        var sections: [TOCSection] = []
        var current: TOCSection?
        var trailing: [TOCNode] = []

        for node in nodes {
            if trailingTitles.contains(node.t) {
                trailing.append(node)
                continue
            }
            if isSeparator(node) {
                if let section = current { sections.append(section) }
                let title = node.t.trimmingCharacters(in: CharacterSet(charactersIn: "—-─ "))
                current = TOCSection(title: title.isEmpty ? "其他" : title, nodes: [])
                continue
            }
            if current == nil {
                pinned.append(node)
            } else {
                current?.nodes.append(node)
            }
        }
        if let section = current { sections.append(section) }

        var result: [TOCSection] = []
        if !pinned.isEmpty {
            result.append(TOCSection(title: "开始阅读", nodes: pinned, isPinned: true))
        }
        result.append(contentsOf: sections.filter { !$0.nodes.isEmpty })
        if !trailing.isEmpty {
            result.append(TOCSection(title: "其他", nodes: trailing, isPinned: true))
        }
        return result
    }
}
