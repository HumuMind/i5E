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

/// 阅读器里需要跨启动记住的杂项状态。
public struct ReaderState: Codable, Sendable {
    /// 目录里手动展开过的节点（用节点的路径标识）。
    public var expandedNodes: Set<String> = []
    /// 最近打开过的页面，最新在前。
    public var recentPages: [RecentPage] = []
    /// 搜索过的词，最新在前。
    public var searchHistory: [String] = []

    public init() {}
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
