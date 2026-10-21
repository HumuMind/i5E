import XCTest

/// UI 冒烟测试的起点。目前只验证「能启动、能搜到东西」这一条主链路，
/// 具体用例等 UI 稳定后再补。
final class SmokeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndSearch() throws {
        let app = XCUIApplication()
        // 先结束可能残留的实例：macOS 上另一个实例占着前台时，
        // 新实例的窗口可能拿不到可查询的层次结构。
        app.terminate()
        app.launch()

        // 侧栏搜索框出现 = 内容库打开、目录加载完成
        let field = app.textFields[AccessibilityID.sidebarSearch]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "侧栏搜索框没有出现，内容库可能没打开")

        field.click()
        field.typeText("火球")

        // 有结果 = 搜索链路通（FTS 召回 + 正文校验 + 列表渲染）
        let firstResult = app.buttons.containing(
            NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.searchResult)
        ).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 20), "搜索没有返回结果")
    }
}

/// 与 App 侧保持一致的标识符，集中在这里方便对照。
enum AccessibilityID {
    static let sidebarSearch = "sidebar.search"
    static let searchResult = "search.result."
    static let tocRow = "toc.row."
    static let readerContent = "reader.content"
}
