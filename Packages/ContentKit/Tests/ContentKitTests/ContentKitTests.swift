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

    /// 目录分组：上游用分隔节点切章节，应该切出 6 个正文章节
    func testTOCSections() async throws {
        let db = try database()
        let toc = try await db.tableOfContents()
        let sections = TOCSectionBuilder.build(from: toc.nodes)
        let titles = sections.map(\.title)
        XCTAssertTrue(titles.contains("核心规则"))
        XCTAssertTrue(titles.contains("战役设定"))
        XCTAssertTrue(titles.contains("合作内容"))
        XCTAssertEqual(sections.first?.title, "开始阅读")
        XCTAssertEqual(sections.last?.title, "其他")
        // 每一本 2014 版的书都还在某个章节里
        let all = sections.flatMap(\.nodes).map(\.t)
        XCTAssertTrue(all.contains("玩家手册2014（旧版）"))
    }

    /// 命中定位：搜到的 block 序号应该真的包含该词
    func testSearchHitBlockIndex() async throws {
        let db = try database()
        let hits = try await db.search("火球", limit: 5)
        let hit = try XCTUnwrap(hits.first)
        let fetched = try await db.page(id: hit.pageID)
        let page = try XCTUnwrap(fetched)
        XCTAssertTrue(0..<page.blocks.count ~= hit.blockIndex)
    }

    // MARK: - 表格列宽

    private func table(_ json: String) throws -> Block {
        try JSONDecoder().decode(Block.self, from: Data(json.utf8))
    }

    /// 两列表：序号列应该被压到下限，描述列拿走大部分宽度
    func testTwoColumnWidths() throws {
        let block = try table(
            """
            {"type":"table","rows":[
              {"cells":[{"blocks":[{"type":"p","runs":[{"t":"1d6"}]}]},
                        {"blocks":[{"type":"p","runs":[{"t":"霜巨人的躯体，配以食人魔的头颅"}]}]}]},
              {"cells":[{"blocks":[{"type":"p","runs":[{"t":"2"}]}]},
                        {"blocks":[{"type":"p","runs":[{"t":"石巨人下半身配巨魔上半身"}]}]}]}
            ]}
            """)
        let widths = TableLayoutCalculator.widths(block, fontSize: 19, available: 720)
        XCTAssertEqual(widths.count, 2)
        XCTAssertLessThan(widths[0], widths[1] / 3)
        XCTAssertLessThanOrEqual(widths.reduce(0, +), 720.5)
    }

    /// 14 列表：每列都不低于下限，总和不超过可用宽度
    func testManyColumnWidths() throws {
        let cells = (0..<14).map { "{\"blocks\":[{\"type\":\"p\",\"runs\":[{\"t\":\"力量\($0)\"}]}]}" }
        let row = "{\"cells\":[" + cells.joined(separator: ",") + "]}"
        let block = try table("{\"type\":\"table\",\"rows\":[\(row)]}")
        let widths = TableLayoutCalculator.widths(block, fontSize: 13, available: 720)
        XCTAssertEqual(widths.count, 14)
        let floor =
            CGFloat(TableLayoutCalculator.minUnits) * 13 / 2
            + TableLayoutCalculator.horizontalPadding
        XCTAssertTrue(widths.allSatisfy { $0 >= floor - 0.5 })
        XCTAssertLessThanOrEqual(widths.reduce(0, +), 720.5)
    }

    /// 窄表保持自然宽度，不铺满
    func testNarrowTableKeepsNaturalWidth() throws {
        let block = try table(
            """
            {"type":"table","rows":[{"cells":[
              {"blocks":[{"type":"p","runs":[{"t":"AC"}]}]},
              {"blocks":[{"type":"p","runs":[{"t":"17"}]}]}
            ]}]}
            """)
        let widths = TableLayoutCalculator.widths(block, fontSize: 13, available: 720)
        XCTAssertLessThan(widths.reduce(0, +), 200)
    }

    func testQueryBuilding() {
        XCTAssertEqual(SearchQuery.matchExpression(for: "龙"), "\"龙\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "火球"), "\"火球\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "魔法飞弹"), "\"魔法\" AND \"法飞\" AND \"飞弹\"")
        XCTAssertNil(SearchQuery.matchExpression(for: "   "))
    }
}
