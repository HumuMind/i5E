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

    init() {
        // 同步恢复上次位置：UserDefaults 读取不需要等异步启动，
        // 这样第一帧就有页面（内容会短暂转圈，但不会闪出空白占位）。
        if let last = store.loadPosition() {
            routes = [Route(path: last.path, offset: last.offset)]
        }
        // 调试与截图用：`-openPage <路径>` 直接打开某一页
        if let raw = UserDefaults.standard.string(forKey: "openPage"), !raw.isEmpty {
            routes = [Route(path: raw)]
        }
    }

    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var toc: TOC?

    var results: [SearchHit] = []
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
    var currentPage: Page?
    var currentOffset = 0

    /// 抽屉与设置由模型持有，菜单命令才能驱动它们。
    var showDrawer = false
    var showSearch = false
    var showSettings = false
    /// 每次自增表示"请聚焦搜索框"。
    var searchFocusToken = 0
    /// 目录里所有可打开页面的顺序，用于上一页/下一页。
    var orderedPaths: [String] = []
    /// 页面路径 → 它所在分支的节点标识（用于自动展开目录）。
    var ancestorNodes: [String: [String]] = [:]

    /// 跨启动保存的杂项状态：目录展开、最近查看、搜索历史。
    var state = ReaderState()
    var expandedNodes: Set<String> { state.expandedNodes }
    var recentPages: [RecentPage] { state.recentPages }
    var searchHistory: [String] { state.searchHistory }
    var query: String = ""
    var isSearching = false

    var db: ContentDatabase?
    let store: ReadingStore = UserDefaultsReadingStore()
    var bookmarks: [Bookmark] = []
    /// 阅读排版尺寸，随字号档位变化。
    var metrics: ReadingMetrics = .standard
    private(set) var pageCount = 0
    /// 内容库的构建信息（上游版本），显示在设置页。
    private(set) var contentBuild: ContentBuild?
    /// 页面路径 → 从顶层到该页的标题链，用于显示"章节路径"。
    var chapterPath: [String: [String]] = [:]
    var searchTask: Task<Void, Never>?

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
            // 内容库随包分发、构建后不会变：按内容哈希记住"已检查通过"，
            // 后续启动跳过（quick_check 在 Mac 上就要 200 ms）。
            let digest = (try? await database.metaValue("text_sha256")) ?? ""
            let integrityKey = "integrity.ok.\(digest.prefix(16))"
            if !UserDefaults.standard.bool(forKey: integrityKey) {
                if let problem = await database.integrityReport() {
                    phase = .failed(problem)
                    return
                }
                UserDefaults.standard.set(true, forKey: integrityKey)
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
            if let seeded = UserDefaults.standard.string(forKey: "searchQuery"), !seeded.isEmpty {
                showSearch = true
                updateQuery(seeded)
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
            if routes.isEmpty, let first = orderedPaths.first {
                // 首次启动直接进第一页，不显示空白占位
                routes = [Route(path: first)]
            }
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
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
