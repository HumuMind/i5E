import ContentKit
import Foundation

extension AppModel {

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
        // 单字查询在中文里几乎命中全库，除了噪音没有信息量
        guard trimmed.count >= 2 else {
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
