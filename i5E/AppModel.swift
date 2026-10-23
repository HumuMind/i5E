import Foundation

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
import Observation
import ContentKit

/// 应用状态。数据访问全部走 ContentKit，这里只管界面需要的东西。
@MainActor
@Observable
final class AppModel {

    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var toc: TOC?

    private(set) var results: [SearchHit] = []
    /// 一页的打开方式：路径 + 锚点 / 命中位置 / 高亮词。
    struct Route: Hashable {
        var path: String
        var anchor: String? = nil
        var blockIndex: Int? = nil
        var highlight: String? = nil
        /// 正文字符偏移；自动恢复上次位置时用。
        var offset: Int? = nil
    }

    /// 详情列的导航栈。
    var routes: [Route] = []
    /// 当前正在显示的页面与位置，供浮动按钮（书签）使用。
    private(set) var currentPage: Page?
    private(set) var currentOffset = 0
    var query: String = ""
    private(set) var isSearching = false

    private var db: ContentDatabase?
    private let store: ReadingStore = UserDefaultsReadingStore()
    private(set) var bookmarks: [Bookmark] = []
    /// 阅读排版尺寸，随字号档位变化。
    private(set) var metrics: ReadingMetrics = .standard
    private(set) var pageCount = 0
    /// 页面路径 → 从顶层到该页的标题链，用于显示"章节路径"。
    private(set) var chapterPath: [String: [String]] = [:]
    private var searchTask: Task<Void, Never>?

    // MARK: - 启动

    func start() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            guard let url = Bundle.main.url(forResource: "content", withExtension: "db") else {
                phase = .failed("内容库 content.db 没有打进应用包")
                return
            }
            let database = try await Signpost.measure("openDatabase") {
                try ContentDatabase(url: url)
            }
            db = database
            let tree = try await Signpost.measure("loadTOC") {
                try await database.tableOfContents()
            }
            toc = tree
            chapterPath = Self.buildChapterPaths(TOCSectionBuilder.build(from: tree.nodes))

            bookmarks = store.bookmarks()

            // 调试与截图用：`-openPage <路径>` 直接打开某一页
            if let path = UserDefaults.standard.string(forKey: "openPage"), !path.isEmpty {
                routes = [Route(path: path)]
            }

            if let size = store.loadFontSize() {
                metrics = .forSize(size)
            }
            if let raw = try? await database.metaValue("pages"),
                let data = raw.data(using: .utf8),
                let count = try? JSONDecoder().decode(Int.self, from: data)
            {
                pageCount = count
            }
            if let last = store.loadPosition() {
                routes = [
                    Route(path: last.path, offset: last.offset)
                ]
            }
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    // MARK: - 阅读

    // MARK: - 导航

    func show(_ route: Route) {
        routes = [route]
    }

    /// 页面所属的章节链，比如「玩家手册2024 › 第一章：进行游戏 › 玩家还是DM？」。
    func pathTitles(for pagePath: String) -> [String] {
        chapterPath[pagePath] ?? []
    }

    /// 记录阅读位置。滚动时高频调用，写 UserDefaults 很便宜，但仍然只在变化时写。
    func recordPosition(path: String, offset: Int, snippet: String) {
        let current = store.loadPosition()
        if let current, current.path == path, abs(current.offset - offset) < 80 { return }
        store.savePosition(
            ReadingPosition(path: path, offset: offset, snippet: snippet))
    }

    func setFontStep(_ step: ReadingMetrics.Step) {
        metrics = step.metrics
        store.saveFontSize(step.rawValue)
    }

    func refreshBookmarks() {
        bookmarks = store.bookmarks()
    }

    func toggleBookmark(path: String, offset: Int, title: String, snippet: String) {
        if let existing = store.bookmarks().first(where: {
            $0.path == path && abs($0.offset - offset) < 200
        }) {
            store.remove(id: existing.id)
        } else {
            store.add(
                Bookmark(
                    path: path, offset: offset, title: title.isEmpty ? path : title,
                    snippet: snippet))
        }
        refreshBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        store.remove(id: bookmark.id)
        refreshBookmarks()
    }

    func isBookmarked(path: String, offset: Int) -> Bool {
        store.isBookmarked(path: path, offset: offset)
    }

    /// 页面是否属于「旧版内容」那一章。
    func isLegacy(path: String) -> Bool {
        chapterPath[path]?.first == "旧版内容"
    }

    /// 把目录摊平成"页面路径 → 标题链"。
    ///
    /// 章节名来自 `TOCSectionBuilder` 的分组（分隔节点变成章节标题），
    /// 所以「旧版内容」会出现在链首——版本判定不需要另建映射表。
    private static func buildChapterPaths(_ sections: [TOCSection]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        func walk(_ list: [TOCNode], trail: [String]) {
            for node in list {
                let next = trail + [node.t]
                if let url = node.u {
                    let key = url.split(separator: "#").first.map(String.init) ?? url
                    map[key] = next
                }
                walk(node.c, trail: next)
            }
        }
        for section in sections {
            walk(section.nodes, trail: section.isPinned ? [] : [section.title])
        }
        return map
    }

    func setCurrent(page: Page?, offset: Int) {
        currentPage = page
        currentOffset = offset
    }

    func setCurrentOffset(_ offset: Int) {
        currentOffset = offset
    }

    func goBack() {
        guard routes.count > 1 else { return }
        routes.removeLast()
    }

    func push(_ route: Route) {
        routes.append(route)
    }

    func page(path: String) async throws -> Page? {
        guard let db else { return nil }
        return try await db.page(path: path)
    }

    /// 处理正文里的链接：外链出去，本页锚点原地滚，跨页压栈。
    func handleLink(_ url: URL) {
        if let scheme = url.scheme?.lowercased(),
            ["http", "https", "mailto"].contains(scheme)
        {
            #if canImport(UIKit)
                UIApplication.shared.open(url)
            #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
            #endif
            return
        }

        let (path, anchor) = Page.splitURL(url)
        if let path, !path.isEmpty {
            push(Route(path: path, anchor: anchor))
        } else if let anchor, let current = routes.last {
            push(Route(path: current.path, anchor: anchor))
        }
    }

    // MARK: - 搜索

    func updateQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    private func runSearch(_ text: String) async {
        guard let db else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let hits = try await Signpost.measure("search") {
                try await db.search(text, limit: 80)
            }
            if !Task.isCancelled { results = hits }
        } catch {
            results = []
        }
    }

    /// 全库正文哈希自检，只在调试时按需调用。
    func verifyContentDigest() async -> Bool {
        guard let db else { return false }
        return (try? await db.verifyTextDigest()) ?? false
    }
}
