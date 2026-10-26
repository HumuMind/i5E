import SwiftUI
import ContentKit

@main
struct i5EApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // 字号在这里下发一次；ReaderView / ReferenceView 只读不覆盖
                .environment(\.readingMetrics, model.metrics)
                .task { await model.start() }
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            // 单窗口：去掉「新建窗口」
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("阅读") {
                Button("搜索正文") { model.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("上一页") { model.goToAdjacentPage(-1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("下一页") { model.goToAdjacentPage(1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("添加或移除书签") { model.toggleBookmarkAtCurrent() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("放大字号") { model.stepFont(1) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("缩小字号") { model.stepFont(-1) }
                    .keyboardShortcut("-", modifiers: .command)
            }
        }
    }
}
