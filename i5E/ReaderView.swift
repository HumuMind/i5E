import ContentKit
import SwiftUI

/// 排版常量，来自 Docs/decisions/0011-typography.md。
enum Reading {
    static let measure: CGFloat = 720  // 版心
    static let bodySize: CGFloat = 19  // 正文字号
    static let lineHeightMultiple: CGFloat = 1.8
    static var lineSpacing: CGFloat { bodySize * (lineHeightMultiple - 1) }
}

struct ReaderView: View {
    let page: Page
    var highlight: String?
    var scrollTarget: Int?

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ReadingTheme { .resolve(colorScheme) }

    /// 阅读区实际宽度，表格按它算列宽（窄屏时小于版心）。
    @State private var contentWidth: CGFloat = Reading.measure

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { index, block in
                        BlockView(
                            block: block, highlight: highlight, availableWidth: contentWidth
                        )
                        .id(index)
                    }
                }
                .frame(maxWidth: Reading.measure, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    contentWidth = width
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
            }
            .background(theme.background)
            .task(id: scrollTarget) {
                guard let scrollTarget else { return }
                // 等一帧，等布局出来再滚，否则 scrollTo 会落空
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
        }
        .environment(\.readingTheme, theme)
        .environment(
            \.openURL,
            OpenURLAction { url in
                model.handleLink(url)
                return .handled
            }
        )
        .navigationTitle(page.title.isEmpty ? page.path : page.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// 按路由加载页面；锚点在这里解析成 block 序号。
struct PageScreen: View {
    let route: AppModel.Route

    @Environment(AppModel.self) private var model
    @State private var page: Page?
    @State private var target: Int?

    var body: some View {
        Group {
            if let page {
                ReaderView(page: page, highlight: route.highlight, scrollTarget: target)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: route) { await load() }
    }

    private func load() async {
        let loaded = try? await model.page(path: route.path)
        page = loaded
        guard let loaded else { return }
        if let index = route.blockIndex {
            target = index
        } else if let anchor = route.anchor {
            target = loaded.blockIndex(forAnchor: anchor)
        } else {
            target = nil
        }
    }
}
