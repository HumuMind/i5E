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

/// 存储接口。现在只有 UserDefaults 实现；换文件或 iCloud 时只换这里。
public protocol ReadingStore: Sendable {
    func loadPosition() -> ReadingPosition?
    func savePosition(_ position: ReadingPosition)
    func bookmarks() -> [Bookmark]
    func add(_ bookmark: Bookmark)
    func remove(id: UUID)
    func isBookmarked(path: String, offset: Int) -> Bool
}

public final class UserDefaultsReadingStore: ReadingStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let positionKey = "reading.position"
    private let bookmarksKey = "reading.bookmarks"
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

    private func persist(_ list: [Bookmark]) {
        guard let data = try? encoder.encode(list) else { return }
        defaults.set(data, forKey: bookmarksKey)
    }
}
