import SwiftUI
import ContentKit

@main
struct i5EApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // 单窗口：靠 Info.plist 的 UIApplicationSupportsMultipleScenes=false 关掉
        // iPad 的"新建窗口"（见 0052）。窗口之间共享同一个 AppModel，
        // 真开出第二个只会显示同一页、共用历史。
        WindowGroup {
            RootView()
                .environment(model)
                // 字号在这里下发一次；ReaderView / ReferenceView 只读不覆盖
                .environment(\.readingMetrics, model.metrics)
                .environment(\.mentionLevel, model.mentionLevel)
                .task { await model.start() }
                #if os(macOS)
                    .onAppear { Snapshot.captureIfRequested() }
                #endif
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            // 单窗口：去掉「新建窗口」，改成新建标签页
            CommandGroup(replacing: .newItem) {
                Button("新建标签页") { model.newTab() }
                    .keyboardShortcut(model.shortcut(for: .newTab).keyboardShortcut)
            }
            CommandGroup(after: .newItem) {
                Button("关闭标签页") { model.closeActiveTab() }
                    .keyboardShortcut(model.shortcut(for: .closeTab).keyboardShortcut)
                    .disabled(model.tabs.count <= 1)
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("阅读") {
                Button("后退") { model.goBack() }
                    .keyboardShortcut(model.shortcut(for: .back).keyboardShortcut)
                    .disabled(!model.canGoBack)
                Button("前进") { model.goForward() }
                    .keyboardShortcut(model.shortcut(for: .forward).keyboardShortcut)
                    .disabled(!model.canGoForward)
                Divider()
                Button("搜索正文") { model.focusSearch() }
                    .keyboardShortcut(model.shortcut(for: .search).keyboardShortcut)
                Button("上一页") { model.goToAdjacentPage(-1) }
                    .keyboardShortcut(model.shortcut(for: .previousPage).keyboardShortcut)
                Button("下一页") { model.goToAdjacentPage(1) }
                    .keyboardShortcut(model.shortcut(for: .nextPage).keyboardShortcut)
                Divider()
                Button("添加或移除书签") { model.toggleBookmarkAtCurrent() }
                    .keyboardShortcut(model.shortcut(for: .toggleBookmark).keyboardShortcut)
                Divider()
                Button("放大字号") { model.stepFont(1) }
                    .keyboardShortcut(model.shortcut(for: .increaseFont).keyboardShortcut)
                Button("缩小字号") { model.stepFont(-1) }
                    .keyboardShortcut(model.shortcut(for: .decreaseFont).keyboardShortcut)
            }
        }
    }
}
