import Foundation

/// 阅读位置：页面 + 正文字符偏移。
///
/// 用字符偏移而不是块序号——中位页只有 5 个块，块序号等于"半页"精度；
/// 字符偏移与字号无关，文本微调时也只是偏移一点点。
public struct ReadingPosition: Codable, Sendable, Hashable {
    public var path: String
    public var offset: Int
    /// 该位置所在段落的前若干字，用于内容更新后重新定位。
    public var snippet: String
    public var updated: Date

    public init(path: String, offset: Int, snippet: String, updated: Date = .now) {
        self.path = path
        self.offset = offset
        self.snippet = snippet
        self.updated = updated
    }
}

public struct Bookmark: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var path: String
    public var offset: Int
    public var title: String
    public var snippet: String
    public var created: Date

    public init(
        id: UUID = UUID(), path: String, offset: Int, title: String, snippet: String,
        created: Date = .now
    ) {
        self.id = id
        self.path = path
        self.offset = offset
        self.title = title
        self.snippet = snippet
        self.created = created
    }
}

/// 最近看过的页面。
public struct RecentPage: Codable, Sendable, Identifiable, Hashable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var visited: Date

    public init(path: String, title: String, visited: Date = .now) {
        self.path = path
        self.title = title
        self.visited = visited
    }
}

/// 一个可配置的快捷键：主键 + 修饰键。
///
/// `key` 是单个字符（如 "f"、"="、"]"），或特殊键的固定名字（"upArrow"、"return"）。
/// 用普通字符串而不是 SwiftUI 的 KeyEquivalent，是为了让 ContentKit 不依赖 UI 框架。
public struct KeyShortcut: Codable, Sendable, Hashable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        key: String, command: Bool = false, shift: Bool = false, option: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

/// 一个标签页的持久化快照。
///
/// 只存当前页和滚动位置：返回/前进历史是会话内的，重启后不恢复。
public struct TabSnapshot: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var path: String
    public var offset: Int

    public init(id: UUID = UUID(), title: String, path: String, offset: Int) {
        self.id = id
        self.title = title
        self.path = path
        self.offset = offset
    }
}

/// 阅读器里需要跨启动记住的杂项状态。
public struct ReaderState: Codable, Sendable {
    /// 目录里手动展开过的节点（用节点的路径标识）。
    public var expandedNodes: Set<String> = []
    /// 目录里手动折叠过的节点。显式折叠优先于"当前页所在分支自动展开"，见 0038 补记。
    public var collapsedNodes: Set<String> = []
    /// 最近打开过的页面，最新在前。
    public var recentPages: [RecentPage] = []
    /// 搜索过的词，最新在前。
    public var searchHistory: [String] = []
    /// 标签页，顺序就是 tab 条里的顺序。
    public var tabs: [TabSnapshot] = []
    /// 当前标签页；写在 tabs 的 id 上，找不到时回落到第一个。
    public var activeTabID: UUID?
    /// 自定义快捷键：动作标识 → 按键。没有的动作用默认值。
    public var shortcuts: [String: KeyShortcut] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case expandedNodes, collapsedNodes, recentPages, searchHistory, tabs, activeTabID
        case shortcuts
    }

    /// 手写解码：旧版本没有 `collapsedNodes` / `tabs` 等字段，缺字段时按空值处理，
    /// 否则升级后会把整份 `ReaderState` 当作损坏而丢掉。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expandedNodes =
            try container.decodeIfPresent(Set<String>.self, forKey: .expandedNodes) ?? []
        collapsedNodes =
            try container.decodeIfPresent(Set<String>.self, forKey: .collapsedNodes) ?? []
        recentPages =
            try container.decodeIfPresent([RecentPage].self, forKey: .recentPages) ?? []
        searchHistory =
            try container.decodeIfPresent([String].self, forKey: .searchHistory) ?? []
        tabs = try container.decodeIfPresent([TabSnapshot].self, forKey: .tabs) ?? []
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        shortcuts =
            try container.decodeIfPresent([String: KeyShortcut].self, forKey: .shortcuts) ?? [:]
    }
}

extension ReaderState {
    /// 目录节点是否展开。优先级：手动折叠 > 手动展开 > 当前页所在分支自动展开。
    ///
    /// `ancestors` 是"页面路径 → 从顶层到该页的节点标识链"，由 TOC 构建时生成。
    /// 手动折叠必须压过自动展开：当前页就在这一节里时，用户也应该能把目录折起来。
    public func isTOCNodeExpanded(
        _ nodeID: String, currentPath: String?, ancestors: [String: [String]]
    ) -> Bool {
        if collapsedNodes.contains(nodeID) { return false }
        if expandedNodes.contains(nodeID) { return true }
        guard let currentPath else { return false }
        return ancestors[currentPath]?.contains(nodeID) ?? false
    }
}

/// 存储接口。现在只有 UserDefaults 实现；换文件或 iCloud 时只换这里。
public protocol ReadingStore: Sendable {
    func loadPosition() -> ReadingPosition?
    func savePosition(_ position: ReadingPosition)
    func bookmarks() -> [Bookmark]
    func add(_ bookmark: Bookmark)
    func remove(id: UUID)
    func isBookmarked(path: String, offset: Int) -> Bool
    func loadFontSize() -> Double?
    func saveFontSize(_ size: Double)
    /// 自动链接的详细程度：0 关闭 / 1 精简 / 2 标准 / 3 详细（见 0051）。
    /// 没设置过返回 nil，调用方用默认值。
    func loadMentionLevel() -> Int?
    func saveMentionLevel(_ level: Int)
    func loadState() -> ReaderState
    func saveState(_ state: ReaderState)
}

public final class UserDefaultsReadingStore: ReadingStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let positionKey = "reading.position"
    private let bookmarksKey = "reading.bookmarks"
    private let fontSizeKey = "reading.fontSize"
    private let mentionLevelKey = "reading.mentionLevel"
    /// 旧版本只有开/关，读到时迁移一次
    private let legacyAutoLinksKey = "reading.autoLinks"
    private let stateKey = "reading.state"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadPosition() -> ReadingPosition? {
        guard let data = defaults.data(forKey: positionKey) else { return nil }
        return try? decoder.decode(ReadingPosition.self, from: data)
    }

    public func savePosition(_ position: ReadingPosition) {
        guard let data = try? encoder.encode(position) else { return }
        defaults.set(data, forKey: positionKey)
    }

    public func bookmarks() -> [Bookmark] {
        guard let data = defaults.data(forKey: bookmarksKey),
            let list = try? decoder.decode([Bookmark].self, from: data)
        else { return [] }
        return list.sorted { $0.created > $1.created }
    }

    public func add(_ bookmark: Bookmark) {
        var list = bookmarks()
        list.removeAll { $0.path == bookmark.path && abs($0.offset - bookmark.offset) < 200 }
        list.append(bookmark)
        persist(list)
    }

    public func remove(id: UUID) {
        var list = bookmarks()
        list.removeAll { $0.id == id }
        persist(list)
    }

    public func isBookmarked(path: String, offset: Int) -> Bool {
        bookmarks().contains { $0.path == path && abs($0.offset - offset) < 200 }
    }

    public func loadFontSize() -> Double? {
        let value = defaults.double(forKey: fontSizeKey)
        return value > 0 ? value : nil
    }

    public func saveFontSize(_ size: Double) {
        defaults.set(size, forKey: fontSizeKey)
    }

    public func loadMentionLevel() -> Int? {
        if defaults.object(forKey: mentionLevelKey) != nil {
            return min(max(defaults.integer(forKey: mentionLevelKey), 0), 3)
        }
        if defaults.object(forKey: legacyAutoLinksKey) != nil {
            return defaults.bool(forKey: legacyAutoLinksKey) ? 2 : 0
        }
        return nil
    }

    public func saveMentionLevel(_ level: Int) {
        defaults.set(min(max(level, 0), 3), forKey: mentionLevelKey)
    }

    public func loadState() -> ReaderState {
        guard let data = defaults.data(forKey: stateKey),
            let state = try? decoder.decode(ReaderState.self, from: data)
        else { return ReaderState() }
        return state
    }

    public func saveState(_ state: ReaderState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func persist(_ list: [Bookmark]) {
        guard let data = try? encoder.encode(list) else { return }
        defaults.set(data, forKey: bookmarksKey)
    }
}
