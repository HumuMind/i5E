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
