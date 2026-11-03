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
        #if DEBUG
            // UI 测试用独立 suite，别碰用户自己的阅读状态和快捷键
            if let suite = UserDefaults.standard.string(forKey: "testDefaultsSuite"),
                let defaults = UserDefaults(suiteName: suite)
            {
                store = UserDefaultsReadingStore(defaults: defaults)
            } else {
                store = UserDefaultsReadingStore()
            }
        #else
            store = UserDefaultsReadingStore()
        #endif

        // 同步恢复状态：UserDefaults 读取不需要等异步启动，
        // 这样第一帧就有页面（内容会短暂转圈，但不会闪出空白占位）。
        state = store.loadState()
        restoreTabs()
        // 调试与截图用：`-openPage <路径>` 直接打开某一页（替换当前标签页）
        if let raw = UserDefaults.standard.string(forKey: "openPage"), !raw.isEmpty {
            routes = [Route(path: raw)]
            routeOffsets = [0]
            forwardRoutes = []
            forwardOffsets = []
            saveActiveTab()
        } else {
            loadActiveTab()
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

    /// 一个标签页的会话状态。
    ///
    /// 只有当前标签页的 `routes` 等字段直接放在 `AppModel` 上；切走时
    /// `loadActiveTab` / `saveActiveTab` 负责在两者之间搬运。
    struct Tab: Identifiable {
        let id: UUID
        var title: String
        var routes: [Route]
        var routeOffsets: [Int]
        var forwardRoutes: [Route]
        var forwardOffsets: [Int]
    }

    /// 详情列的导航栈。
    var routes: [Route] = []
    /// 与 `routes` 一一对应：每页离开时的滚动位置（字符偏移），返回时用它复位。
    var routeOffsets: [Int] = []
    /// 后退时弹出的页面，按弹出的先后顺序存放；最后一个就是"前进"要去的那页。
    var forwardRoutes: [Route] = []
    /// 与 `forwardRoutes` 一一对应。
    var forwardOffsets: [Int] = []
    /// 标签页；顺序就是 tab 条里的顺序。
    var tabs: [Tab] = []
    /// 当前标签页。切 tab 时先保存旧页、再装载新页。
    var activeTabID = UUID()
    /// 每次前进/后退自增。页面视图以它为 id，导航时整体重建。
    var navigationToken = 0
    /// 最近一次导航的方向：+1 前进 / -1 返回。转场据此决定从哪边滑入。
    var navigationDirection = 0
    /// 最近读过的页：返回时直接拿它做首帧，避免闪一下空白
    @ObservationIgnored var pageCache: [String: Page] = [:]
    @ObservationIgnored var pageCacheOrder: [String] = []
    /// 当前正在显示的页面与位置，供浮动按钮（书签）使用。
    var currentPage: Page?
    var currentOffset = 0

    /// 抽屉与设置由模型持有，菜单命令才能驱动它们。
    var showDrawer = false
    var showSearch = false
    var showSettings = false
    /// 每次自增表示"请聚焦搜索框"。
    var searchFocusToken = 0
    /// 快捷键改过之后自增，Mac 菜单据此同步。
    var shortcutRevision = 0
    /// 正在录制快捷键：全局的关闭标签页监听要让路。
    var isRecordingShortcut = false
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
    let store: ReadingStore
    var bookmarks: [Bookmark] = []
    /// 阅读排版尺寸，随字号档位变化。
    var metrics: ReadingMetrics = .standard
    /// 正文里的自动链接详细程度：0 关闭 / 1 精简 / 2 标准 / 3 详细（见 0051）
    var mentionLevel = 2
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
            if let level = store.loadMentionLevel() {
                mentionLevel = level
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
                routeOffsets = [0]
                saveActiveTab()
                persistTabs()
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
