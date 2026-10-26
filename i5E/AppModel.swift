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

    /// 抽屉与设置由模型持有，菜单命令才能驱动它们。
    var showDrawer = false
    var showSearch = false
    var showSettings = false
    /// 每次自增表示"请聚焦搜索框"。
    private(set) var searchFocusToken = 0
    /// 目录里所有可打开页面的顺序，用于上一页/下一页。
    private(set) var orderedPaths: [String] = []
    /// 页面路径 → 它所在分支的节点标识（用于自动展开目录）。
    private(set) var ancestorNodes: [String: [String]] = [:]

    /// 跨启动保存的杂项状态：目录展开、最近查看、搜索历史。
    private var state = ReaderState()
    var expandedNodes: Set<String> { state.expandedNodes }
    var recentPages: [RecentPage] { state.recentPages }
    var searchHistory: [String] { state.searchHistory }
    var query: String = ""
    private(set) var isSearching = false

    private var db: ContentDatabase?
    private let store: ReadingStore = UserDefaultsReadingStore()
    private(set) var bookmarks: [Bookmark] = []
    /// 阅读排版尺寸，随字号档位变化。
    private(set) var metrics: ReadingMetrics = .standard
    private(set) var pageCount = 0
    /// 内容库的构建信息（上游版本），显示在设置页。
    private(set) var contentBuild: ContentBuild?
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
            let built = Self.buildChapterPaths(TOCSectionBuilder.build(from: tree.nodes))
            chapterPath = built.paths
            orderedPaths = built.order
            ancestorNodes = built.ancestors
            state = store.loadState()

            bookmarks = store.bookmarks()
            showDrawer = UserDefaults.standard.bool(forKey: "openDrawer")
            showSearch = UserDefaults.standard.bool(forKey: "openSearch")
            showSettings = UserDefaults.standard.bool(forKey: "openSettings")

            // 调试与截图用：`-openPage <路径>` 直接打开某一页
            if let path = UserDefaults.standard.string(forKey: "openPage"), !path.isEmpty {
                routes = [Route(path: path)]
            }

            if let size = store.loadFontSize() {
                metrics = .forSize(size)
            }
            if let raw = try? await database.metaValue("build"),
                let data = raw.data(using: .utf8)
            {
                contentBuild = try? JSONDecoder().decode(ContentBuild.self, from: data)
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
    private static func buildChapterPaths(
        _ sections: [TOCSection]
    ) -> (paths: [String: [String]], order: [String], ancestors: [String: [String]]) {
        var map: [String: [String]] = [:]
        var ordered: [String] = []
        var ancestors: [String: [String]] = [:]
        func walk(_ list: [TOCNode], trail: [String], chain: [String]) {
            for node in list {
                let next = trail + [node.t]
                let nextChain = chain + [node.id]
                if let url = node.u {
                    let key = url.split(separator: "#").first.map(String.init) ?? url
                    map[key] = next
                    ancestors[key] = nextChain
                    if !ordered.contains(key) { ordered.append(key) }
                }
                walk(node.c, trail: next, chain: nextChain)
            }
        }
        for section in sections {
            walk(section.nodes, trail: section.isPinned ? [] : [section.title], chain: [])
        }
        return (map, ordered, ancestors)
    }

    func setCurrent(page: Page?, offset: Int) {
        currentPage = page
        currentOffset = offset
        if let page { rememberVisit(page) }
    }

    /// 记一次访问；同一页重复打开只更新时间并提到最前。
    private func rememberVisit(_ page: Page) {
        state.recentPages.removeAll { $0.path == page.path }
        state.recentPages.insert(
            RecentPage(path: page.path, title: page.title.isEmpty ? page.path : page.title),
            at: 0)
        if state.recentPages.count > 30 { state.recentPages.removeLast(30) }
        store.saveState(state)
    }

    func toggleExpansion(_ nodeID: String) {
        if state.expandedNodes.contains(nodeID) {
            state.expandedNodes.remove(nodeID)
        } else {
            state.expandedNodes.insert(nodeID)
        }
        store.saveState(state)
    }

    /// 目录某节点是否展开：手动展开过，或它在当前页面的分支上。
    func isExpanded(_ nodeID: String) -> Bool {
        if let current = routes.last?.path,
            ancestorNodes[current]?.contains(nodeID) == true
        {
            return true
        }
        return state.expandedNodes.contains(nodeID)
    }

    func recordSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        state.searchHistory.removeAll { $0 == trimmed }
        state.searchHistory.insert(trimmed, at: 0)
        if state.searchHistory.count > 20 { state.searchHistory.removeLast(20) }
        store.saveState(state)
    }

    func clearSearchHistory() {
        state.searchHistory = []
        store.saveState(state)
    }

    func clearRecentPages() {
        state.recentPages = []
        store.saveState(state)
    }

    func setCurrentOffset(_ offset: Int) {
        currentOffset = offset
    }

    func focusSearch() {
        showDrawer = false
        showSearch = true
        searchFocusToken += 1
    }

    func goToAdjacentPage(_ delta: Int) {
        guard !orderedPaths.isEmpty else { return }
        let current = routes.last?.path
        let index = current.flatMap { orderedPaths.firstIndex(of: $0) } ?? -1
        let next = index < 0 ? 0 : index + delta
        guard orderedPaths.indices.contains(next) else { return }
        show(Route(path: orderedPaths[next]))
    }

    func stepFont(_ delta: Int) {
        let steps = ReadingMetrics.Step.allCases
        let current = steps.firstIndex { $0.rawValue == metrics.bodySize } ?? 1
        let next = min(max(current + delta, 0), steps.count - 1)
        setFontStep(steps[next])
    }

    func toggleBookmarkAtCurrent() {
        guard let page = currentPage else { return }
        toggleBookmark(
            path: page.path, offset: currentOffset, title: page.title,
            snippet: PageText.snippet(at: currentOffset, in: page.blocks))
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

/// `content.db` 里 `build` 字段的结构，只取展示需要的部分。
struct ContentBuild: Decodable, Sendable {
    struct Upstream: Decodable, Sendable {
        var short: String
        var date: String
        var subject: String?
    }

    var upstream: Upstream

    /// `2026-10-15`，从 ISO 时间戳里截日期。
    var upstreamDate: String {
        String(upstream.date.prefix(10))
    }
}
