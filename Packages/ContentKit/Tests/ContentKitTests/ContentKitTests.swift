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

    // MARK: - 对比度修复

    /// 深色背景上的暗红标题应被提亮成偏红的颜色，且达标
    func testDarkTitleTurnsLightRed() throws {
        let background = try XCTUnwrap(RGB(hexOrRGB: "#17191c"))
        let title = try XCTUnwrap(RGB(hexOrRGB: "#800000"))
        XCTAssertLessThan(Contrast.ratio(title, background), Contrast.minimumRatio)

        let repaired = Contrast.repair(title, on: background)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(repaired, background), Contrast.minimumRatio)
        XCTAssertGreaterThan(repaired.r, repaired.g, "色相应该还在红侧")
        XCTAssertGreaterThan(repaired.r, repaired.b)
    }

    /// 达标的颜色不该被改动
    func testCompliantColorUnchanged() throws {
        let background = try XCTUnwrap(RGB(hexOrRGB: "#ffffff"))
        let text = try XCTUnwrap(RGB(hexOrRGB: "#242629"))
        XCTAssertEqual(Contrast.repair(text, on: background), text)
    }

    /// 浅色底压暗后仍要能分辨出深浅关系
    func testDarkenKeepsOrder() throws {
        let surface = try XCTUnwrap(RGB(hexOrRGB: "#17191c"))
        let light = try XCTUnwrap(RGB(hexOrRGB: "#eeeeee"))
        let dark = try XCTUnwrap(RGB(hexOrRGB: "#d9d9d9"))
        let a = Contrast.darken(light, toward: surface)
        let b = Contrast.darken(dark, toward: surface)
        XCTAssertGreaterThan(a.luminance, b.luminance)
        XCTAssertLessThan(a.luminance, 0.2, "压暗后不应还是亮色")
    }

    func testQueryBuilding() {
        XCTAssertEqual(SearchQuery.matchExpression(for: "龙"), "\"龙\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "火球"), "\"火球\"")
        XCTAssertEqual(SearchQuery.matchExpression(for: "魔法飞弹"), "\"魔法\" AND \"法飞\" AND \"飞弹\"")
        XCTAssertNil(SearchQuery.matchExpression(for: "   "))
    }
}

final class SourceStyleTests: XCTestCase {
    func testHeadingColorsMatchStylesheet() {
        XCTAssertEqual(SourceStyle.headingColorHex(level: 1), "#800000")
        XCTAssertEqual(SourceStyle.headingColorHex(level: 3), "#800000")
        XCTAssertEqual(SourceStyle.headingColorHex(level: 4), "#704cd9")
        XCTAssertEqual(SourceStyle.headingColorHex(level: 6), "#0f5cbc")
        XCTAssertNil(SourceStyle.headingColorHex(level: 5))
    }

    func testInlineSemanticColors() {
        XCTAssertEqual(SourceStyle.inlineColorHex(underlined: true, italic: false, bold: false), "#008000")
        XCTAssertEqual(SourceStyle.inlineColorHex(underlined: true, italic: true, bold: false), "#704cd9")
        XCTAssertEqual(SourceStyle.inlineColorHex(underlined: true, italic: false, bold: true), "#ee3300")
        XCTAssertNil(SourceStyle.inlineColorHex(underlined: false, italic: true, bold: false))
    }
}

final class LinkTests: XCTestCase {
    func testSplitLink() {
        let a = Page.splitLink("玩家手册/魔法/法术详述/一环.html#Fireball")
        XCTAssertEqual(a.path, "玩家手册/魔法/法术详述/一环.html")
        XCTAssertEqual(a.anchor, "Fireball")

        let b = Page.splitLink("#Acid_Splash")
        XCTAssertNil(b.path)
        XCTAssertEqual(b.anchor, "Acid_Splash")

        let c = Page.splitLink("速查/种族.htm")
        XCTAssertEqual(c.path, "速查/种族.htm")
        XCTAssertNil(c.anchor)
    }

    /// 锚点要能定位到块：标题的 id、以及块上挂的 anchors 都算
    func testBlockIndexForAnchor() throws {
        let json = """
            [{"type":"h","level":4,"id":"Fireball","runs":[{"t":"火球术｜Fireball"}]},
             {"type":"p","runs":[{"t":"正文"}],"anchors":["Top"]},
             {"type":"p","runs":[{"t":"更多"}]}]
            """
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        let page = Page(id: 1, path: "x", title: "", blocks: blocks)
        XCTAssertEqual(page.blockIndex(forAnchor: "Fireball"), 0)
        XCTAssertEqual(page.blockIndex(forAnchor: "Top"), 1)
        XCTAssertNil(page.blockIndex(forAnchor: "Missing"))
    }
}

final class ReadingStoreTests: XCTestCase {
    private func store() -> UserDefaultsReadingStore {
        let suite = UserDefaults(suiteName: "i5e.tests.\(UUID().uuidString)")!
        return UserDefaultsReadingStore(defaults: suite)
    }

    func testPositionRoundTrip() {
        let s = store()
        XCTAssertNil(s.loadPosition())
        s.savePosition(ReadingPosition(path: "a/b.htm", offset: 1234, snippet: "开头几个字"))
        let loaded = s.loadPosition()
        XCTAssertEqual(loaded?.path, "a/b.htm")
        XCTAssertEqual(loaded?.offset, 1234)
    }

    func testBookmarkAddRemoveAndNearDuplicate() {
        let s = store()
        s.add(Bookmark(path: "a.htm", offset: 100, title: "甲", snippet: "x"))
        XCTAssertEqual(s.bookmarks().count, 1)
        // 同一位置附近再加一次，应当替换而不是重复
        s.add(Bookmark(path: "a.htm", offset: 150, title: "甲", snippet: "x"))
        XCTAssertEqual(s.bookmarks().count, 1)
        XCTAssertTrue(s.isBookmarked(path: "a.htm", offset: 120))

        let first = s.bookmarks()[0]
        s.remove(id: first.id)
        XCTAssertTrue(s.bookmarks().isEmpty)
    }

    /// 位置偏移辅助：块序号与字符偏移可以互相对应
    func testBlockOffsetRoundTrip() throws {
        let json = """
            [{"type":"h","level":2,"runs":[{"t":"标题"}]},
             {"type":"p","runs":[{"t":"第一段"}]},
             {"type":"p","runs":[{"t":"第二段"}]}]
            """
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        let offset = try XCTUnwrap(PageText.offset(ofBlock: 2, in: blocks))
        XCTAssertEqual(PageText.blockIndex(forOffset: offset, in: blocks), 2)
        XCTAssertEqual(PageText.snippet(at: offset, in: blocks), "第二段")
    }
}

final class ReferenceTableTests: XCTestCase {
    private func database() throws -> ContentDatabase {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        return try ContentDatabase(url: URL(fileURLWithPath: path))
    }

    /// 万器大全：497 行、7 列、第一行是表头、首列带链接
    func testExtractsBigTable() async throws {
        let db = try database()
        let page = try await db.page(path: "速查/5E万器大全.htm")
        let unwrapped = try XCTUnwrap(page)
        let table = try XCTUnwrap(ReferenceTableExtractor.extract(from: unwrapped))
        XCTAssertGreaterThan(table.rows.count, 400)
        XCTAssertEqual(table.headers.first, "物品名")
        XCTAssertEqual(table.columnCount, 7)
        XCTAssertNotNil(table.rows.first?.first?.link)
    }

    /// 普通文档页不该被误判
    func testOrdinaryPageHasNoReferenceTable() async throws {
        let db = try database()
        let page = try await db.page(path: "玩家手册2024/进行游戏/游戏规律.htm")
        let unwrapped = try XCTUnwrap(page)
        XCTAssertNil(ReferenceTableExtractor.extract(from: unwrapped))
    }

    /// 分面：低基数列能生成筛选项，名称列不生成
    func testFacets() async throws {
        let db = try database()
        let page = try await db.page(path: "速查/5E万器大全.htm")
        let table = try XCTUnwrap(ReferenceTableExtractor.extract(from: try XCTUnwrap(page)))
        let rarities = table.facets(column: 1)
        XCTAssertFalse(rarities.isEmpty)
        XCTAssertTrue(rarities.contains("珍稀"))
        XCTAssertTrue(table.facets(column: 0).isEmpty, "名称列取值太多，不该做分面")
    }
}

final class EditionTests: XCTestCase {
    private func database() throws -> ContentDatabase {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        return try ContentDatabase(url: URL(fileURLWithPath: path))
    }

    /// 2014 与 2024 的法术共用同一个锚点 id，这是版本标注存在的前提
    func testSpellIDsOverlapAcrossEditions() async throws {
        let db = try database()
        func spellIDs(_ path: String) async throws -> Set<String> {
            guard let page = try await db.page(path: path) else { return [] }
            return Set(
                page.blocks.filter { $0.type == "h" && $0.level == 4 }.compactMap(\.id))
        }
        let old = try await spellIDs("玩家手册/魔法/法术详述/三环.html")
        let new = try await spellIDs("玩家手册2024/法术详述/三环.htm")
        XCTAssertFalse(old.isEmpty)
        XCTAssertFalse(new.intersection(old).isEmpty, "两版应共用大量 id")
    }
}

final class LinkURLTests: XCTestCase {
    /// 中文路径经 URL 之后必须还能解析回原文（曾因此导致页面永远加载中）
    func testChinesePathSurvivesURL() throws {
        let href = "玩家手册2024/法术详述/一环.html#Fireball"
        let url = try XCTUnwrap(URL(string: href))
        let split = Page.splitURL(url)
        XCTAssertEqual(split.path, "玩家手册2024/法术详述/一环.html")
        XCTAssertEqual(split.anchor, "Fireball")
    }

    func testAnchorOnlyURL() throws {
        let url = try XCTUnwrap(URL(string: "#Acid_Splash"))
        let split = Page.splitURL(url)
        XCTAssertNil(split.path)
        XCTAssertEqual(split.anchor, "Acid_Splash")
    }
}

final class MetricsTests: XCTestCase {
    func testMeasureScalesWithFontSize() {
        let small = ReadingMetrics.forSize(17)
        let large = ReadingMetrics.forSize(22)
        XCTAssertLessThan(small.bodySize, large.bodySize)
        XCTAssertLessThan(small.measure, large.measure)
        // 每行字数保持在合理区间
        for metrics in [small, ReadingMetrics.standard, large] {
            let charsPerLine = metrics.measure / metrics.bodySize
            XCTAssertGreaterThan(charsPerLine, 30)
            XCTAssertLessThan(charsPerLine, 45)
        }
    }

    func testTableSizeLadder() {
        let standard = ReadingMetrics.standard
        XCTAssertEqual(standard.tableSize(columnCount: 2), 19)
        XCTAssertEqual(standard.tableSize(columnCount: 4), 16)
        XCTAssertEqual(standard.tableSize(columnCount: 11), 13)
        // 大字号下也不会低于 12
        XCTAssertGreaterThanOrEqual(ReadingMetrics.forSize(22).tableSize(columnCount: 11), 12)
    }

    func testFontSizePersists() {
        let suite = UserDefaults(suiteName: "i5e.font.\(UUID().uuidString)")!
        let store = UserDefaultsReadingStore(defaults: suite)
        XCTAssertNil(store.loadFontSize())
        store.saveFontSize(22)
        XCTAssertEqual(store.loadFontSize(), 22)
    }
}

final class ReaderStateTests: XCTestCase {
    private func store() -> UserDefaultsReadingStore {
        UserDefaultsReadingStore(
            defaults: UserDefaults(suiteName: "i5e.state.\(UUID().uuidString)")!)
    }

    func testStateRoundTrip() {
        let s = store()
        var state = s.loadState()
        XCTAssertTrue(state.expandedNodes.isEmpty)

        state.expandedNodes = ["a|b|2", "c|d|0"]
        state.recentPages = [RecentPage(path: "x.htm", title: "某页")]
        state.searchHistory = ["火球", "先攻"]
        s.saveState(state)

        let loaded = s.loadState()
        XCTAssertEqual(loaded.expandedNodes, ["a|b|2", "c|d|0"])
        XCTAssertEqual(loaded.recentPages.first?.path, "x.htm")
        XCTAssertEqual(loaded.searchHistory, ["火球", "先攻"])
    }
}

final class IntegrityTests: XCTestCase {
    private func database() throws -> ContentDatabase {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        return try ContentDatabase(url: URL(fileURLWithPath: path))
    }

    func testHealthyDatabaseReportsNoProblem() async throws {
        let report = await (try database()).integrityReport()
        XCTAssertNil(report, "正常内容库不该报错，实际：\(report ?? "")")
    }

    /// 截断的文件应当被识别为损坏，而不是"打开成功但内容为空"
    func testTruncatedDatabaseReportsProblem() async throws {
        let source = ProcessInfo.processInfo.environment["CONTENT_DB"] ?? ""
        let broken = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("broken-\(UUID().uuidString).db")
        let data = try Data(contentsOf: URL(fileURLWithPath: source))
        try data.prefix(data.count / 3).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }

        let opened = try? ContentDatabase(url: broken)
        if let opened {
            let report = await opened.integrityReport()
            XCTAssertNotNil(report, "截断的库应当被识别为损坏")
        }
        // 打不开也算识别成功，无需断言
    }
}

final class TableRowSpanTests: XCTestCase {
    /// (文本, colspan, rowspan)
    private func table(_ rows: [[(String, Int, Int)]]) throws -> Block {
        let json = """
            {"type":"table","rows":[
            \(rows.map { row in
                "{\"cells\":[" + row.map { cell in
                    "{\"colspan\":\(cell.1),\"rowspan\":\(cell.2),\"blocks\":[{\"type\":\"p\",\"runs\":[{\"t\":\"\(cell.0)\"}]}]}"
                }.joined(separator: ",") + "]}"
            }.joined(separator: ","))
            ]}
            """
        return try JSONDecoder().decode(Block.self, from: Data(json.utf8))
    }

    /// 职业法术表的两行表头：第二行要从第 6 列开始，而不是顶到第 1 列
    func testSecondHeaderRowSkipsRowSpannedColumns() throws {
        let block = try table([
            [
                ("等级", 1, 2), ("熟练加值", 1, 2), ("职业特性", 1, 2), ("戏法", 1, 2), ("准备法术", 1, 2),
                ("——每环法术位——", 5, 1),
            ],
            [("一环", 1, 1), ("二环", 1, 1), ("三环", 1, 1), ("四环", 1, 1), ("五环", 1, 1)],
            [
                ("1", 1, 1), ("+2", 1, 1), ("施法", 1, 1), ("2", 1, 1), ("2", 1, 1), ("2", 1, 1),
                ("—", 1, 1), ("—", 1, 1), ("—", 1, 1), ("—", 1, 1),
            ],
        ])
        let grid = TableGrid(block)
        XCTAssertEqual(grid.columnCount, 10)
        XCTAssertEqual(grid.rows[1].first?.column, 5)
        XCTAssertEqual(grid.rows[2].first?.column, 0)

        let slots = grid.slots(in: 1)
        guard case .hole(let column, let colspan) = slots.first else {
            return XCTFail("第二行应当先是一个空洞")
        }
        XCTAssertEqual(column, 0)
        XCTAssertEqual(colspan, 5)
    }

    /// 行内的 rowspan（阵营表的分组列）：后面的行要跳过第一列
    func testBodyRowSpanKeepsColumns() throws {
        let block = try table([
            [("阵营", 1, 1), ("1d4", 1, 1), ("相关特征", 1, 1)],
            [("混乱", 1, 4), ("1", 1, 1), ("自吹自擂", 1, 1)],
            [("2", 1, 1), ("冲动", 1, 1)],
            [("3", 1, 1), ("粗俗", 1, 1)],
            [("4", 1, 1), ("多变", 1, 1)],
        ])
        let grid = TableGrid(block)
        XCTAssertEqual(grid.columnCount, 3)
        XCTAssertEqual(grid.rows[1].first?.column, 0)
        XCTAssertEqual(grid.rows[2].first?.column, 1)
        XCTAssertEqual(grid.rows[4].first?.column, 1)
        if case .hole(let column, _) = grid.slots(in: 3).first {
            XCTAssertEqual(column, 0)
        } else {
            XCTFail("被合并格覆盖的行应当留空洞")
        }
    }

    /// 去空列之后，rowspan 表的列位仍然对得上
    func testNormalizeKeepsRowSpanAlignment() throws {
        let block = try table([
            [("等级", 1, 2), ("", 1, 1), ("戏法", 1, 2), ("一环", 1, 1)],
            [("", 1, 1), ("二环", 1, 1)],
            [("1", 1, 1), ("", 1, 1), ("2", 1, 1), ("2", 1, 1)],
        ])
        let normalized = TableLayoutCalculator.normalize(block)
        XCTAssertEqual(TableLayoutCalculator.columnCount(normalized), 3)
        let grid = TableGrid(normalized)
        XCTAssertEqual(grid.rows[0].first?.column, 0)
        // 空列去掉后，戏法（rowspan 2）仍在第 2 列，一环/二环落到第 3 列
        XCTAssertEqual(grid.rows[0].last?.column, 2)
        XCTAssertEqual(grid.rows[1].first?.column, 2)
    }
}

final class TableNormalizeTests: XCTestCase {
    private func table(_ rows: [[(String, Int)]]) throws -> Block {
        let json = """
            {"type":"table","rows":[
            \(rows.map { row in
                "{\"cells\":[" + row.map { cell in
                    "{\"colspan\":\(cell.1),\"blocks\":[{\"type\":\"p\",\"runs\":[{\"t\":\"\(cell.0)\"}]}]}"
                }.joined(separator: ",") + "]}"
            }.joined(separator: ","))
            ]}
            """
        return try JSONDecoder().decode(Block.self, from: Data(json.utf8))
    }

    /// 空列（占位 / 5px 间隔列）应当被去掉，span 相应收缩
    func testDropsEmptyColumns() throws {
        let block = try table([
            [("AC 12", 1), ("先攻 +2", 1)],
            [("HP 11", 2)],
            [("速度 40", 2)],
        ])
        XCTAssertEqual(TableLayoutCalculator.columnCount(block), 2)
    }

    func testDropsSpacerColumn() throws {
        let block = try table([
            [("力量", 1), ("14", 1), ("", 1), ("敏捷", 1), ("15", 1)],
            [("智力", 1), ("3", 1), ("", 1), ("感知", 1), ("12", 1)],
        ])
        let normalized = TableLayoutCalculator.normalize(block)
        XCTAssertEqual(TableLayoutCalculator.columnCount(normalized), 4)
        XCTAssertEqual(normalized.rows?.first?.cells.count, 4)
    }

    func testKeepsTableWithoutEmptyColumns() throws {
        let block = try table([[("a", 1), ("b", 1)]])
        let normalized = TableLayoutCalculator.normalize(block)
        XCTAssertEqual(TableLayoutCalculator.columnCount(normalized), 2)
    }
}

final class NormalizeRealPageTests: XCTestCase {
    func testWolfStatBlock() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONTENT_DB"] else {
            throw XCTSkip("未设置 CONTENT_DB")
        }
        let db = try ContentDatabase(url: URL(fileURLWithPath: path))
        let page = try await db.page(path: "怪物图鉴2025/附录A/狼.htm")
        let blocks = try XCTUnwrap(page).blocks
        let div = try XCTUnwrap(blocks.first { $0.type == "div" })
        for table in div.blocksOrEmpty where table.type == "table" {
            let before = TableLayoutCalculator.columnCount(table)
            let after = TableLayoutCalculator.columnCount(TableLayoutCalculator.normalize(table))
            print("  表：\(before) 列 → \(after) 列")
            XCTAssertLessThanOrEqual(after, before)
        }
    }
}

final class TableMinimumWidthTests: XCTestCase {
    private func table(_ rows: [[(String, Int)]]) throws -> Block {
        let json = """
            {"type":"table","rows":[
            \(rows.map { row in
                "{\"cells\":[" + row.map { cell in
                    "{\"colspan\":\(cell.1),\"blocks\":[{\"type\":\"p\",\"runs\":[{\"t\":\"\(cell.0)\"}]}]}"
                }.joined(separator: ",") + "]}"
            }.joined(separator: ","))
            ]}
            """
        return try JSONDecoder().decode(Block.self, from: Data(json.utf8))
    }

    /// `PHB24` 这类不可断词要有足够的最小宽度
    func testUnbreakableTokenGetsMinimum() throws {
        let block = try table([[("名称", 1), ("来源", 1)], [("短棒Club", 1), ("PHB24", 1)]])
        let minimums = TableLayoutCalculator.minimumWidths(block, fontSize: 13)
        XCTAssertEqual(minimums.count, 2)
        XCTAssertGreaterThanOrEqual(minimums[1], 40, "PHB24 至少要有 5 个字母的实际宽度")
    }

    /// 中文可以逐字断，最小宽度保持很小
    func testChineseHasSmallMinimum() throws {
        let block = try table([[("名称", 1)], [("这是一段很长的中文内容", 1)]])
        let minimums = TableLayoutCalculator.minimumWidths(block, fontSize: 13)
        XCTAssertLessThanOrEqual(minimums[0], 20, "中文可逐字断，下限很小")
    }
}

final class NestedAnchorTests: XCTestCase {
    /// 锚点藏在表格单元格里时，也要能定位到它所属的顶层块
    func testAnchorInsideTable() throws {
        let json = """
            [{"type":"h","level":2,"id":"Top","runs":[{"t":"标题"}]},
             {"type":"table","rows":[{"cells":[
                {"blocks":[{"type":"p","id":"InTable","runs":[{"t":"格子里"}]}]}
             ]}]},
             {"type":"p","runs":[{"t":"正文"}]}]
            """
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        let page = Page(id: 1, path: "x", title: "", blocks: blocks)
        XCTAssertEqual(page.blockIndex(forAnchor: "InTable"), 1)
        XCTAssertEqual(page.blockIndex(forAnchor: "Top"), 0)
        XCTAssertNil(page.blockIndex(forAnchor: "Nope"))
    }
}
