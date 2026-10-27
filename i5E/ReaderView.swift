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
    /// 顶部留白，避免内容被浮动按钮遮住。
    var topInset: CGFloat = 0
    /// 滚动时回报当前顶部 block 的字符偏移。
    var onPositionChange: ((Int) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readingMetrics) private var metrics

    private var theme: ReadingTheme { .resolve(colorScheme) }

    /// 阅读区实际宽度，表格按它算列宽（窄屏时小于版心）。
    /// 滚动区域宽度（未被版心约束），版心由它推算。
    @State private var viewportWidth: CGFloat = ReadingMetrics.standard.measure

    private var measureWidth: CGFloat { metrics.measure(forAvailable: viewportWidth) }
    @State private var topBlock: Int?
    /// 定位完成前先不画正文：否则会先露一眼页首，再跳到目标位置
    @State private var readyToShow: Bool

    init(
        page: Page, highlight: String? = nil, scrollTarget: Int? = nil,
        topInset: CGFloat = 0, onPositionChange: ((Int) -> Void)? = nil
    ) {
        self.page = page
        self.highlight = highlight
        self.scrollTarget = scrollTarget
        self.topInset = topInset
        self.onPositionChange = onPositionChange
        _topBlock = State(initialValue: scrollTarget)
        _readyToShow = State(initialValue: scrollTarget == nil)
    }

    /// 页面上的一行内容：单块，或"图文并排"组。
    ///
    /// 源页用 `<IMG align=right>` 让文字绕图排列，原生排版没有 float，
    /// 这里把图与紧随其后的几段文字并排，近似出同样的观感。
    private struct BlockGroup: Identifiable {
        enum Kind {
            case single(Int)
            case floating(head: Int, tail: [Int], image: Run)
        }
        var id: Int
        var kind: Kind
    }

    private var groups: [BlockGroup] {
        var result: [BlockGroup] = []
        var index = 0
        let blocks = page.blocks
        while index < blocks.count {
            guard let image = Self.floatedImage(in: blocks[index]) else {
                result.append(BlockGroup(id: index, kind: .single(index)))
                index += 1
                continue
            }
            // 图旁边能放下多少文字：按字数估，最多再带 3 段
            var tail: [Int] = []
            var characters = blocks[index].deepPlainText.count
            var cursor = index + 1
            while cursor < blocks.count, tail.count < 3, characters < 400,
                blocks[cursor].type == "p" || blocks[cursor].type == "h"
            {
                tail.append(cursor)
                characters += blocks[cursor].deepPlainText.count
                cursor += 1
            }
            result.append(
                BlockGroup(id: index, kind: .floating(head: index, tail: tail, image: image)))
            index = cursor
        }
        return result
    }

    private static func floatedImage(in block: Block) -> Run? {
        block.runsOrEmpty.first { $0.img != nil && $0.align == "right" }
    }

    private func floatingGroup(head: Int, tail: [Int], image: Run, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                BlockView(
                    block: page.blocks[head], skipFloatedImage: true, highlight: highlight,
                    availableWidth: width * 0.55
                )
                .id(head)
                ForEach(tail, id: \.self) { index in
                    BlockView(
                        block: page.blocks[index], highlight: highlight,
                        availableWidth: width * 0.55
                    )
                    .id(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ContentImageView(run: image, maxWidth: width * 0.42)
        }
        .padding(.bottom, Reading.bodySize * 0.6)
    }

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
                    ForEach(groups) { group in
                        switch group.kind {
                        case .single(let index):
                            BlockView(
                                block: page.blocks[index], highlight: highlight,
                                availableWidth: measureWidth
                            )
                            .id(index)
                        case .floating(let index, let tail, let image):
                            floatingGroup(
                                head: index, tail: tail, image: image, width: measureWidth)
                        }
                    }
                }
                .scrollTargetLayout()
                .opacity(readyToShow ? 1 : 0)
                .frame(maxWidth: measureWidth, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 40 + topInset)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
                .accessibilityIdentifier("reader.content")
            }
            .background(theme.background)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                viewportWidth = width
            }
            .scrollPosition(id: $topBlock)
            .onChange(of: topBlock) { _, newValue in
                // 立即回报：返回上一页时要用最新位置，不能等防抖
                guard let newValue,
                    let offset = PageText.offset(ofBlock: newValue, in: page.blocks)
                else { return }
                onPositionChange?(offset)
            }
            .task(id: "bottom-\(UserDefaults.standard.bool(forKey: "scrollBottom"))") {
                // 调试：`-scrollBottom 1` 启动后滚到页尾，方便检查底部内容
                guard UserDefaults.standard.bool(forKey: "scrollBottom"),
                    !page.blocks.isEmpty
                else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(page.blocks.count - 1, anchor: .bottom)
            }
            .task(id: scrollTarget) {
                guard let scrollTarget else {
                    readyToShow = true
                    return
                }
                // 等一帧把布局算出来再滚，否则 scrollTo 会落空。
                // 这期间正文是不可见的：先露页首再跳会看起来像卡了一下。
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(scrollTarget, anchor: .top)
                readyToShow = true
            }
        }
        .environment(\.readingTheme, theme)
        .environment(\.usesStyleSheet, page.usesStyleSheet)
        .environment(
            \.openURL,
            OpenURLAction { url in
                model.handleLink(url)
                return .handled
            }
        )
        .hideNavigationChrome()
    }
}

/// 按路由加载页面；锚点在这里解析成 block 序号。
struct PageScreen: View {
    let route: AppModel.Route
    /// 栈顶那一层上次读到哪（返回时用它复位，前进时为 0）
    let resume: Int

    @Environment(AppModel.self) private var model
    @State private var page: Page?
    @State private var target: Int?
    @State private var currentOffset = 0
    @State private var failed = false
    @State private var saveTask: Task<Void, Never>?

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
                    topInset: 48,
                    onPositionChange: { offset in
                        currentOffset = offset
                        model.setCurrentOffset(offset)
                        // 落盘防抖：滚动时别每一帧都写 UserDefaults
                        saveTask?.cancel()
                        saveTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            model.recordPosition(
                                path: page.path, offset: offset,
                                snippet: PageText.snippet(at: offset, in: page.blocks))
                        }
                    }
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: route) { await load() }
        .onChange(of: model.phase) { _, newValue in
            if case .ready = newValue, page == nil {
                Task { await load() }
            }
        }
    }

    /// 有缓存页时，目标 block 在第一帧就算好：否则会先露一下页首再跳。
    init(route: AppModel.Route, resume: Int = 0, initialPage: Page? = nil) {
        self.route = route
        self.resume = resume
        _page = State(initialValue: initialPage)
        _target = State(
            initialValue: initialPage.flatMap {
                Self.startBlock(route: route, resume: resume, page: $0)
            })
    }

    /// 这一页该落到哪个 block：优先用"上次读到哪"，其次搜索命中/锚点。
    static func startBlock(route: AppModel.Route, resume: Int, page: Page) -> Int? {
        if resume > 0 {
            return PageText.blockIndex(forOffset: resume, in: page.blocks) ?? 0
        }
        if let index = route.blockIndex { return index }
        if let anchor = route.anchor { return page.blockIndex(forAnchor: anchor) }
        return nil
    }

    private func load() async {
        // 库还没打开时不要判定失败：等 phase 变成 ready 会自动重试
        guard model.isReady else { return }
        failed = false
        let loaded: Page?
        if let page, page.path == route.path {
            loaded = page
        } else {
            loaded = try? await Signpost.measure("loadPage") {
                try await model.page(path: route.path)
            }
        }
        page = loaded
        if let loaded { model.rememberPage(loaded) }
        guard let loaded else {
            failed = true
            model.setCurrent(page: nil, offset: 0)
            return
        }
        let start = Self.startBlock(route: route, resume: resume, page: loaded)
        target = start
        currentOffset = start.flatMap { PageText.offset(ofBlock: $0, in: loaded.blocks) } ?? 0
        model.setCurrent(page: loaded, offset: currentOffset)
    }
}
