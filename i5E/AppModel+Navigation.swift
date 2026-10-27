import ContentKit
import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension AppModel {

    /// 打开一页。目录选页与链接跳转都追加到历史，返回按钮才有东西可回。
    func show(_ route: Route) {
        if routes.last?.path == route.path, route.offset == nil, route.blockIndex == nil {
            return
        }
        routes.append(route)
        if routes.count > 50 { routes.removeFirst(routes.count - 50) }
    }

    /// 页面所属的章节链，比如「玩家手册2024 › 第一章：进行游戏 › 玩家还是DM？」。
    func pathTitles(for pagePath: String) -> [String] {
        chapterPath[pagePath] ?? []
    }

    /// 页面是否属于「旧版内容」那一章。
    func isLegacy(path: String) -> Bool {
        chapterPath[path]?.first == "旧版内容"
    }

    /// 把目录摊平成"页面路径 → 标题链"。
    ///
    /// 章节名来自 `TOCSectionBuilder` 的分组（分隔节点变成章节标题），
    /// 所以「旧版内容」会出现在链首——版本判定不需要另建映射表。
    static func buildChapterPaths(
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

    func focusSearch() {
        closeDrawer()
        showSearch = true
        searchFocusToken += 1
    }

    /// 收起目录抽屉。
    ///
    /// Mac 上目录常驻左侧，没有可收起的抽屉，这个动作要直接落空（见 0050）。
    func closeDrawer() {
        #if os(iOS)
            showDrawer = false
        #endif
    }

    func goToAdjacentPage(_ delta: Int) {
        guard !orderedPaths.isEmpty else { return }
        let current = routes.last?.path
        let index = current.flatMap { orderedPaths.firstIndex(of: $0) } ?? -1
        let next = index < 0 ? 0 : index + delta
        guard orderedPaths.indices.contains(next) else { return }
        show(Route(path: orderedPaths[next]))
    }

    func goBack() {
        guard routes.count > 1 else { return }
        routes.removeLast()
    }

    func push(_ route: Route) {
        show(route)
    }

    /// 内容库是否已就绪。页面加载要等它，否则会误判成"这一页打不开"。
    var isReady: Bool {
        if case .ready = phase { return true }
        return false
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
}
