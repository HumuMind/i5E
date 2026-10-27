import ContentKit
import Foundation

extension AppModel {

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

    /// 自动链接的详细程度（见 0051）。只影响渲染，不改内容。
    func setMentionLevel(_ level: Int) {
        mentionLevel = min(max(level, 0), 3)
        store.saveMentionLevel(mentionLevel)
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

    /// 读 `bookmarks` 而不是直接问 store：@Observable 只跟踪被读到的属性，
    /// 走 store 的话界面不会因为书签变化而刷新。
    func isBookmarked(path: String, offset: Int) -> Bool {
        bookmarks.contains { $0.path == path && abs($0.offset - offset) < 200 }
    }

    func setCurrentOffset(_ offset: Int) {
        currentOffset = offset
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

    func clearRecentPages() {
        state.recentPages = []
        store.saveState(state)
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
}
