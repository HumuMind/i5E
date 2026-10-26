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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ReadingTheme { .resolve(colorScheme) }

    /// 阅读区实际宽度，表格按它算列宽（窄屏时小于版心）。
    /// 滚动区域宽度（未被版心约束），版心由它推算。
    @State private var viewportWidth: CGFloat = ReadingMetrics.standard.measure

    private var measureWidth: CGFloat { metrics.measure(forAvailable: viewportWidth) }
    @State private var topBlock: Int?
    @State private var saveTask: Task<Void, Never>?

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
        .hideNavigationChrome()
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
                        model.recordPosition(
                            path: page.path, offset: offset,
                            snippet: PageText.snippet(at: offset, in: page.blocks))
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

    private func load() async {
        // 库还没打开时不要判定失败：等 phase 变成 ready 会自动重试
        guard model.isReady else { return }
        failed = false
        let loaded = try? await Signpost.measure("loadPage") {
            try await model.page(path: route.path)
        }
        page = loaded
        guard let loaded else {
            failed = true
            model.setCurrent(page: nil, offset: 0)
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
        model.setCurrent(page: loaded, offset: currentOffset)
    }
}
