import ContentKit
import SwiftUI

/// 全屏内容 + 浮动按钮 + 抽屉式目录。
///
/// 不再用 `NavigationSplitView`：三个平台共用同一套结构，
/// 因此不需要按 size class 分叉（见 0035）。
/// 左上角按钮开目录，右上角是书签与设置。
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            NavigationStack(path: $model.routes) {
                StartPlaceholder()
                    .navigationDestination(for: AppModel.Route.self) { route in
                        PageScreen(route: route)
                    }
            }
            .hideNavigationChrome()

            if !model.showDrawer {
                FloatingBar(
                    showDrawer: $model.showDrawer, showSettings: $model.showSettings,
                    canGoBack: model.routes.count > 1
                )
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .leading) {
            if model.showDrawer {
                DrawerOverlay(isPresented: $model.showDrawer)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.showDrawer)
        #if os(macOS)
            // Esc 关抽屉（iOS 上没有这个命令）
            .onExitCommand { model.showDrawer = false }
        #endif
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $model.showSearch) {
            SearchPanel()
        }
    }
}

/// 隐藏系统导航栏 / 窗口工具栏：三个平台用不同的 placement。
private struct HideNavigationChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.toolbar(.hidden, for: .navigationBar)
        #else
            content.toolbar(.hidden, for: .windowToolbar)
        #endif
    }
}

extension View {
    func hideNavigationChrome() -> some View {
        modifier(HideNavigationChrome())
    }
}

/// 还没选页面时的占位。
private struct StartPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选一页开始读", systemImage: "book",
            description: Text("左上角的按钮打开目录，也可以在里面搜索"))
    }
}

// MARK: - 浮动按钮

private struct FloatingBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showDrawer: Bool
    @Binding var showSettings: Bool
    var canGoBack: Bool

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            if canGoBack {
                button("chevron.backward", label: "返回") { model.goBack() }
            }
            button("list.bullet", label: "目录") {
                showDrawer.toggle()
            }
            button("magnifyingglass", label: "搜索") {
                model.focusSearch()
            }
            Spacer()
            if let page = model.currentPage {
                button(
                    model.isBookmarked(path: page.path, offset: model.currentOffset)
                        ? "bookmark.fill" : "bookmark",
                    label: "书签"
                ) {
                    model.toggleBookmark(
                        path: page.path, offset: model.currentOffset,
                        title: page.title,
                        snippet: PageText.snippet(at: model.currentOffset, in: page.blocks))
                }
            }
            button("gearshape", label: "设置") { showSettings = true }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canGoBack)
    }

    private func button(
        _ systemName: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: .circle)
                .overlay(Circle().stroke(theme.border.opacity(0.6), lineWidth: 0.5))
                .foregroundStyle(theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 抽屉

private struct DrawerOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }

                VStack(spacing: 0) {
                    HStack {
                        Text("5E 不全书").font(.headline).foregroundStyle(theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    Divider().overlay(theme.border)
                    DrawerContent()
                }
                .frame(width: min(360, proxy.size.width * 0.88))
                .frame(maxHeight: .infinity)
                // 背景铺到状态栏，内容留在安全区内
                .background(theme.surface.ignoresSafeArea(edges: .vertical))
            }
        }
    }
}

private struct DrawerContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("打开内容库…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("内容库无法读取", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Text("请删除本应用后从 App Store 重新下载。内容随应用分发，没有其他修复途径。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .ready:
            TOCTree(nodes: model.toc?.nodes ?? [])
        }
    }
}

// MARK: - 目录树

struct TOCTree: View {
    @Environment(AppModel.self) private var model
    let nodes: [TOCNode]

    private var sections: [TOCSection] { TOCSectionBuilder.build(from: nodes) }

    var body: some View {
        List {
            if !model.bookmarks.isEmpty {
                Section("书签") {
                    ForEach(model.bookmarks) { bookmark in
                        Button {
                            model.show(
                                AppModel.Route(path: bookmark.path, offset: bookmark.offset))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title).lineLimit(1)
                                Text(bookmark.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                model.removeBookmark(bookmark)
                            }
                        }
                    }
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.nodes) { node in
                        NodeRows(node: node, depth: 0)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(section.title)
                        if section.isPinned {
                            Image(systemName: "pin").font(.caption2)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct NodeRows: View {
    @Environment(AppModel.self) private var model
    let node: TOCNode
    let depth: Int

    private var expanded: Binding<Bool> {
        Binding(
            get: { model.isExpanded(node.id) },
            set: { _ in model.toggleExpansion(node.id) })
    }

    var body: some View {
        if node.c.isEmpty {
            Button {
                guard let path = node.u else { return }
                model.show(AppModel.Route(path: path))
            } label: {
                rowLabel(systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .disabled(node.u == nil)
            .accessibilityIdentifier("toc.row.\(node.t)")
        } else {
            DisclosureGroup(isExpanded: expanded) {
                ForEach(node.c) { child in
                    NodeRows(node: child, depth: depth + 1)
                }
            } label: {
                Button {
                    guard let path = node.u else { return }
                    model.show(AppModel.Route(path: path))
                } label: {
                    rowLabel(systemImage: "book.closed")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowLabel(systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(node.t).lineLimit(1)
        }
        .padding(.leading, CGFloat(depth) * 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 搜索结果

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.results.isEmpty {
            ContentUnavailableView(
                "没有匹配", systemImage: "text.magnifyingglass",
                description: Text("试试别的词，或换一个更短的查询"))
        } else {
            List(model.results) { hit in
                Button {
                    model.show(
                        AppModel.Route(
                            path: hit.path, blockIndex: hit.blockIndex, highlight: model.query))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(hit.title.isEmpty ? hit.path : hit.title)
                                .font(.headline)
                            if model.isLegacy(path: hit.path) {
                                Text("旧版")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: .capsule)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(hit.snippet)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        let trail = model.pathTitles(for: hit.path)
                        if !trail.isEmpty {
                            Text(trail.joined(separator: " › "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.result.\(hit.id)")
            }
        }
    }
}

// MARK: - 搜索面板（搜索 / 最近）

struct SearchPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var tab: Tab = .search
    @FocusState private var focused: Bool

    private enum Tab: String, CaseIterable, Identifiable {
        case search = "搜索"
        case recent = "最近"
        var id: String { rawValue }
    }

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                switch tab {
                case .search: searchTab
                case .recent: recentTab
                }
            }
            .navigationTitle("查找")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .onAppear { focused = true }
    }

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                TextField("搜索正文", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .accessibilityIdentifier("sidebar.search")
                    #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { model.recordSearch(query) }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.background, in: .rect(cornerRadius: 8))
            .padding(.horizontal, 16)
            .onChange(of: query) { _, newValue in model.updateQuery(newValue) }
            .onChange(of: model.searchFocusToken) { focused = true }

            if query.isEmpty {
                historyList
            } else {
                SearchResultsView()
            }
        }
    }

    private var historyList: some View {
        List {
            if !model.searchHistory.isEmpty {
                Section("最近搜索") {
                    ForEach(model.searchHistory, id: \.self) { term in
                        Button {
                            query = term
                            model.updateQuery(term)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                Text(term)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if model.searchHistory.isEmpty {
                ContentUnavailableView(
                    "搜点什么", systemImage: "magnifyingglass",
                    description: Text("输入书名、法术名或规则关键词"))
            }
        }
    }

    private var recentTab: some View {
        List {
            if model.recentPages.isEmpty {
                ContentUnavailableView(
                    "还没有阅读记录", systemImage: "clock",
                    description: Text("打开过的页面会出现在这里"))
            } else {
                Section("最近查看") {
                    ForEach(model.recentPages) { page in
                        Button {
                            model.show(AppModel.Route(path: page.path))
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.title).lineLimit(1)
                                Text(model.pathTitles(for: page.path).joined(separator: " › "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .toolbar {
            if !model.recentPages.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清空") { model.clearRecentPages() }
                }
            }
        }
    }
}
