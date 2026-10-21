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
    /// 滚动时回报当前顶部 block 的字符偏移。
    var onPositionChange: ((Int) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readingMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ReadingTheme { .resolve(colorScheme) }

    /// 阅读区实际宽度，表格按它算列宽（窄屏时小于版心）。
    @State private var contentWidth: CGFloat = ReadingMetrics.standard.measure
    @State private var topBlock: Int?
    @State private var saveTask: Task<Void, Never>?

    private var chapterCaption: some View {
        Text(model.pathTitles(for: page.path).joined(separator: " › "))
            .font(.footnote)
            .foregroundStyle(theme.muted)
            .padding(.bottom, 18)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    chapterCaption
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { index, block in
                        BlockView(
                            block: block, highlight: highlight, availableWidth: contentWidth
                        )
                        .id(index)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: metrics.measure, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    contentWidth = width
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
                .accessibilityIdentifier("reader.content")
            }
            .background(theme.background)
            .scrollPosition(id: $topBlock)
            .onChange(of: topBlock) { _, newValue in
                guard let newValue else { return }
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled,
                        let offset = PageText.offset(ofBlock: newValue, in: page.blocks)
                    else { return }
                    onPositionChange?(offset)
                }
            }
            .task(id: scrollTarget) {
                guard let scrollTarget else { return }
                // 等一帧，等布局出来再滚，否则 scrollTo 会落空
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
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
    @State private var currentOffset = 0
    @State private var failed = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if failed {
                ContentUnavailableView(
                    "这一页打不开", systemImage: "exclamationmark.triangle",
                    description: Text(route.path))
            } else if let page, let reference = ReferenceTableExtractor.extract(from: page) {
                ReferenceView(page: page, table: reference)
            } else if let page {
                ReaderView(
                    page: page, highlight: route.highlight, scrollTarget: target,
                    onPositionChange: { offset in
                        currentOffset = offset
                        model.recordPosition(
                            path: page.path, offset: offset,
                            snippet: PageText.snippet(at: offset, in: page.blocks))
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.toggleBookmark(
                                path: page.path, offset: currentOffset,
                                title: page.title,
                                snippet: PageText.snippet(at: currentOffset, in: page.blocks))
                        } label: {
                            Image(
                                systemName: model.isBookmarked(
                                    path: page.path, offset: currentOffset)
                                    ? "bookmark.fill" : "bookmark")
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: route) { await load() }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func load() async {
        failed = false
        let loaded = try? await Signpost.measure("loadPage") {
            try await model.page(path: route.path)
        }
        page = loaded
        guard let loaded else {
            failed = true
            return
        }
        if let offset = route.offset {
            target = PageText.blockIndex(forOffset: offset, in: loaded.blocks) ?? 0
            currentOffset = offset
        } else if let index = route.blockIndex {
            target = index
            currentOffset = PageText.offset(ofBlock: index, in: loaded.blocks) ?? 0
        } else if let anchor = route.anchor, let index = loaded.blockIndex(forAnchor: anchor) {
            target = index
            currentOffset = PageText.offset(ofBlock: index, in: loaded.blocks) ?? 0
        } else {
            target = nil
            currentOffset = 0
        }
    }
}
