import ContentKit
import Foundation

extension AppModel {

    // MARK: - 标签页

    /// 从 `ReaderState` 恢复标签页。
    ///
    /// 历史（返回/前进）是会话内的，重启后每个 tab 只剩当前这一页；
    /// 老版本没有 tabs 时，用 `reading.position` 生成唯一一个 tab。
    func restoreTabs() {
        if !state.tabs.isEmpty {
            tabs = state.tabs.map { snapshot in
                let route =
                    snapshot.path.isEmpty
                    ? nil : Route(path: snapshot.path, offset: snapshot.offset)
                return Tab(
                    id: snapshot.id,
                    title: snapshot.title,
                    routes: route.map { [$0] } ?? [],
                    routeOffsets: route.map { _ in [snapshot.offset] } ?? [],
                    forwardRoutes: [],
                    forwardOffsets: [])
            }
            activeTabID =
                state.activeTabID.flatMap { id in
                    tabs.contains(where: { $0.id == id }) ? id : nil
                } ?? tabs[0].id
        } else {
            let position = store.loadPosition()
            let path = position?.path
            let offset = position?.offset ?? 0
            let route = path.map { Route(path: $0, offset: offset) }
            let tab = Tab(
                id: UUID(),
                title: path.map { tabTitle(for: $0) } ?? "",
                routes: route.map { [$0] } ?? [],
                routeOffsets: route.map { _ in [offset] } ?? [],
                forwardRoutes: [],
                forwardOffsets: [])
            tabs = [tab]
            activeTabID = tab.id
        }
    }

    /// 把当前标签页的状态装进 `routes` 等字段。切 tab 时调用。
    func loadActiveTab() {
        guard let tab = tabs.first(where: { $0.id == activeTabID }) else { return }
        routes = tab.routes
        routeOffsets = tab.routeOffsets
        forwardRoutes = tab.forwardRoutes
        forwardOffsets = tab.forwardOffsets
        currentOffset = tab.routeOffsets.last ?? 0
        currentPage = routes.last.flatMap { pageCache[$0.path] }
        navigationDirection = 0
        navigationToken += 1
    }

    /// 把 `routes` 等字段写回当前标签页。切换、关闭、导航后都要调。
    func saveActiveTab() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        tabs[index].routes = routes
        tabs[index].routeOffsets = routeOffsets
        tabs[index].forwardRoutes = forwardRoutes
        tabs[index].forwardOffsets = forwardOffsets
        // 刚压入新页时 currentPage 还是上一页的，标题要跟着当前路由走
        if let page = currentPage, page.path == routes.last?.path, !page.title.isEmpty {
            tabs[index].title = page.title
        } else if let path = routes.last?.path {
            tabs[index].title = tabTitle(for: path)
        }
    }

    /// 把标签页列表写进 `ReaderState` 并落盘。
    func persistTabs() {
        saveActiveTab()
        state.tabs = tabs.map { tab in
            TabSnapshot(
                id: tab.id,
                title: tab.title,
                path: tab.routes.last?.path ?? "",
                offset: tab.routeOffsets.last ?? 0)
        }
        state.activeTabID = activeTabID
        store.saveState(state)
    }

    func selectTab(_ id: UUID) {
        guard id != activeTabID, tabs.contains(where: { $0.id == id }) else { return }
        saveActiveTab()
        activeTabID = id
        loadActiveTab()
        persistTabs()
    }

    /// 新建标签页：从当前页和当前位置开始，历史为空。
    func newTab() {
        saveActiveTab()
        let path = routes.last?.path
        let offset = currentOffset
        let title: String
        if let page = currentPage, !page.title.isEmpty {
            title = page.title
        } else if let path {
            title = tabTitle(for: path)
        } else {
            title = "新标签页"
        }
        let route = path.map { Route(path: $0, offset: offset) }
        let tab = Tab(
            id: UUID(),
            title: title,
            routes: route.map { [$0] } ?? [],
            routeOffsets: route.map { _ in [offset] } ?? [],
            forwardRoutes: [],
            forwardOffsets: [])
        tabs.append(tab)
        activeTabID = tab.id
        loadActiveTab()
        persistTabs()
    }

    /// 在新标签页直接打开一个目标（Cmd+点击链接用），历史从这一页开始。
    func openInNewTab(_ route: Route) {
        saveActiveTab()
        let tab = Tab(
            id: UUID(),
            title: tabTitle(for: route.path),
            routes: [route],
            routeOffsets: [route.offset ?? 0],
            forwardRoutes: [],
            forwardOffsets: [])
        tabs.append(tab)
        activeTabID = tab.id
        loadActiveTab()
        persistTabs()
    }

    func closeActiveTab() {
        closeTab(activeTabID)
    }

    /// 关闭一个标签页；只剩一个时不允许关。
    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        saveActiveTab()
        let wasActive = id == activeTabID
        tabs.remove(at: index)
        if wasActive {
            activeTabID = tabs[min(index, tabs.count - 1)].id
            loadActiveTab()
        }
        persistTabs()
    }

    /// tab 条上的标题：优先用页面标题，没加载过就用文件名。
    func tabTitle(for path: String) -> String {
        if let page = pageCache[path], !page.title.isEmpty { return page.title }
        let name = (path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "新标签页" : base
    }
}
