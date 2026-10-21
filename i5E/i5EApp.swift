import SwiftUI
import ContentKit

@main
struct i5EApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
        .defaultSize(width: 1100, height: 800)
    }
}
