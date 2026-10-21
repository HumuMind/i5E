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
        var anchor: String?
        var blockIndex: Int?
        var highlight: String?
    }

    /// 详情列的导航栈。
    var routes: [Route] = []
    var query: String = ""
    private(set) var isSearching = false

    private var db: ContentDatabase?
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
            let database = try ContentDatabase(url: url)
            db = database
            toc = try await database.tableOfContents()
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

    func push(_ route: Route) {
        routes.append(route)
    }

    func page(path: String) async throws -> Page? {
        guard let db else { return nil }
        return try await db.page(path: path)
    }

    /// 处理正文里的链接：外链出去，本页锚点原地滚，跨页压栈。
    func handleLink(_ url: URL) {
        let raw = url.relativeString
        if raw.lowercased().hasPrefix("http") {
            #if canImport(UIKit)
                UIApplication.shared.open(url)
            #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
            #endif
            return
        }
        let (path, anchor) = Page.splitLink(raw)
        if let path, !path.isEmpty {
            if let current = routes.last, current.path == path {
                push(Route(path: path, anchor: anchor))
            } else {
                push(Route(path: path, anchor: anchor))
            }
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
            let hits = try await db.search(text, limit: 80)
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
