import XCTest
@testable import ContentKit

final class ContentKitTests: XCTestCase {

    /// 需要一个真实内容库才能跑：CONTENT_DB=…/content.db swift test
    private func database() throws -> ContentDatabase {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        return try ContentDatabase(url: URL(fileURLWithPath: path))
    }

    func testTOCLoads() async throws {
        let db = try database()
        let toc = try await db.tableOfContents()
        XCTAssertFalse(toc.nodes.isEmpty)
        XCTAssertEqual(toc.title, "五版不全书")
    }

    func testPageDecodes() async throws {
        let db = try database()
        let page = try await db.page(path: "玩家手册2024/法术详述/三环.htm")
        let unwrapped = try XCTUnwrap(page)
        XCTAssertFalse(unwrapped.blocks.isEmpty)
        XCTAssertTrue(PageText.of(unwrapped.blocks).contains("火球"))
    }

    func testSearchFindsExpected() async throws {
        let db = try database()
        let hits = try await db.search("火球", limit: 20)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains { $0.snippet.contains("火球") })
    }

    /// 关键检查：Swift 的 PageText 必须与 Python 的 page_text 逐字节一致
    func testTextDigestMatchesBuild() async throws {
        let db = try database()
        let ok = try await db.verifyTextDigest()
        XCTAssertTrue(ok, "PageText 与构建侧不一致，搜索校验会出错")
    }

    func testQueryBuilding() {
        XCTAssertEqual(SearchQuery.matchExpression(for: "龙"), "\"龙\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "火球"), "\"火球\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "魔法飞弹"), "\"魔法\" AND \"法飞\" AND \"飞弹\"")
        XCTAssertNil(SearchQuery.matchExpression(for: "   "))
    }
}
