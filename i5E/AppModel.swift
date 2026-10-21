import Foundation
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
    private(set) var page: Page?
    private(set) var results: [SearchHit] = []
    /// 从搜索结果跳转时要滚动到的位置。
    struct Focus: Hashable {
        var blockIndex: Int
        var query: String
    }

    var selectedPath: String?
    private(set) var focus: Focus?
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

    func open(path: String, blockIndex: Int? = nil, query: String? = nil) async {
        guard let db else { return }
        selectedPath = path
        do {
            let fetched = try await db.page(path: path)
            page = fetched
            if let blockIndex, let query {
                focus = Focus(blockIndex: blockIndex, query: query)
            } else {
                focus = nil
            }
        } catch {
            phase = .failed(String(describing: error))
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
