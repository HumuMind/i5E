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
    }
}
