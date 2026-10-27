import ContentKit
import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension AppModel {

    /// 打开一页。目录选页与链接跳转都追加到历史，返回按钮才有东西可回。
    ///
    /// 目标页先读进内存再推：内容在翻页动画开始前就绪，动画才不会被"内容
    /// 突然出现"打断（否则 SwiftUI 会当成普通更新，直接跳到终态）。
    func show(_ route: Route) {
        if routes.last?.path == route.path, route.offset == nil, route.blockIndex == nil {
            return
        }
        guard pageCache[route.path] == nil else {
            pushNow(route)
            return
        }
        Task {
            _ = try? await page(path: route.path)
            pushNow(route)
        }
    }

    /// 系统开了"减弱动态效果"就不做转场。
    private var reduceMotion: Bool {
        #if canImport(UIKit)
            UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
            false
        #endif
    }

    private var navigationAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    /// 真正入栈。前进前先把当前页的滚动位置记进 `routeOffsets`，返回时才能回到原处。
    private func pushNow(_ route: Route) {
        rememberOffset()
        withAnimation(navigationAnimation) {
            navigationDirection = 1
            routes.append(route)
            // 书签这类自带位置的入口要沿用它的偏移；普通链接从页首开始
            routeOffsets.append(route.offset ?? 0)
            if routes.count > 50 {
                routes.removeFirst(routes.count - 50)
                routeOffsets.removeFirst(routeOffsets.count - 50)
            }
            navigationToken += 1
        }
    }

    /// 把当前页的滚动位置写回栈顶。
    func rememberOffset() {
        guard !routes.isEmpty, routeOffsets.count == routes.count else { return }
        routeOffsets[routes.count - 1] = currentOffset
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
        withAnimation(navigationAnimation) {
            navigationDirection = -1
            routes.removeLast()
            routeOffsets.removeLast()
            navigationToken += 1
        }
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
        if let cached = pageCache[path] { return cached }
        guard let db else { return nil }
        let loaded = try await db.page(path: path)
        if let loaded { rememberPage(loaded) }
        return loaded
    }

    /// 已经读过的页（同步返回，供返回上一页时做首帧）。
    func cachedPage(_ path: String) -> Page? {
        pageCache[path]
    }

    func rememberPage(_ page: Page) {
        if pageCache[page.path] == nil {
            pageCacheOrder.append(page.path)
            if pageCacheOrder.count > 30 {
                pageCache.removeValue(forKey: pageCacheOrder.removeFirst())
            }
        }
        pageCache[page.path] = page
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
