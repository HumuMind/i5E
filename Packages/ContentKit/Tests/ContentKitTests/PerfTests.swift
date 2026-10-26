import XCTest
@testable import ContentKit

/// 数据层基线。跑法：
/// CONTENT_DB=…/content.db swift test --filter PerfTests
final class PerfTests: XCTestCase {

    private func db() throws -> ContentDatabase {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        return try ContentDatabase(url: URL(fileURLWithPath: path))
    }

    private func timed(_ label: String, _ body: () async throws -> Void) async rethrows {
        let start = Date()
        try await body()
        let ms = Date().timeIntervalSince(start) * 1000
        print(String(format: "  %@：%.1f ms", label, ms))
    }

    func testBaseline() async throws {
        let path = ProcessInfo.processInfo.environment["CONTENT_DB"] ?? ""
        print("\n数据层基线（\(path.split(separator: "/").last ?? "")）")

        var database: ContentDatabase!
        try await timed("打开内容库") {
            database = try ContentDatabase(url: URL(fileURLWithPath: path))
            _ = try await database.tableOfContents()
        }

        try await timed("加载目录（8.8k 节点）") {
            _ = try await database.tableOfContents()
        }

        for page in ["玩家手册2024/法术详述/三环.htm", "其他/beyond drops/26.10/渴血魔骸.htm"] {
            try await timed("打开普通页 \(page.prefix(18))") {
                _ = try await database.page(path: page)
            }
        }

        try await timed("打开 970 行参考页") {
            _ = try await database.page(path: "速查/法术速查/5E万法大全.html")
        }

        for query in ["火球", "魔法飞弹", "先攻"] {
            try await timed("搜索「\(query)」") {
                _ = try await database.search(query, limit: 50)
            }
        }

        try await timed("全库正文哈希自检") {
            _ = try await database.verifyTextDigest()
        }
    }
}

/// 搜索质量探针：把结果数量和耗时打出来，便于判断是否需要限制最短查询。
final class SearchQualityTests: XCTestCase {
    func testProbe() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        let db = try ContentDatabase(url: URL(fileURLWithPath: path))
        for query in ["的", "火", "火球", "火球术", "AC", "先攻"] {
            let start = Date()
            let hits = try await db.search(query, limit: 80)
            let ms = Date().timeIntervalSince(start) * 1000
            let head = hits.prefix(3).map(\.title).joined(separator: " | ")
            print(String(format: "  「%@」 %3d 条 · %5.0f ms · %@", query, hits.count, ms, head))
        }
    }
}

final class HeavyPageTests: XCTestCase {
    func testEquipmentPageLayout() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        let db = try ContentDatabase(url: URL(fileURLWithPath: path))
        let start = Date()
        let page = try await db.page(path: "玩家手册/装备/冒险用品.html")
        let blocks = try XCTUnwrap(page).blocks
        print(String(format: "  读取：%.0f ms · 块数 %d", Date().timeIntervalSince(start) * 1000, blocks.count))

        let t2 = Date()
        for block in blocks where block.type == "table" {
            let normalized = TableLayoutCalculator.normalize(block)
            _ = TableLayoutCalculator.widths(normalized, fontSize: 13, available: 700)
        }
        print(String(format: "  表格排版：%.0f ms", Date().timeIntervalSince(t2) * 1000))
    }
}

final class StartupTests: XCTestCase {
    func testStartupPhases() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        var t = Date()
        let db = try ContentDatabase(url: URL(fileURLWithPath: path))
        print(String(format: "  打开库：%.0f ms", Date().timeIntervalSince(t) * 1000))

        t = Date()
        _ = try await db.integrityReport()
        print(String(format: "  完整性检查：%.0f ms", Date().timeIntervalSince(t) * 1000))

        t = Date()
        let toc = try await db.tableOfContents()
        print(String(format: "  目录：%.0f ms（%d 个顶层节点）", Date().timeIntervalSince(t) * 1000, toc.nodes.count))

        t = Date()
        _ = try await db.page(path: "写在前面.html")
        print(String(format: "  首页：%.0f ms", Date().timeIntervalSince(t) * 1000))
    }
}
