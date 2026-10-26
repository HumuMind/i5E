import ContentKit
import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: Tab = .search

    private var queryBinding: Binding<String> {
        Binding(get: { model.query }, set: { model.updateQuery($0) })
    }
    @FocusState private var focused: Bool

    private enum Tab: String, CaseIterable, Identifiable {
        case search = "搜索"
        case recent = "最近"
        var id: String { rawValue }
    }

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
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
        .onAppear { focused = true }
    }

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                TextField("搜索正文", text: queryBinding)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .accessibilityIdentifier("sidebar.search")
                    #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { model.recordSearch(model.query) }
                if !model.query.isEmpty {
                    Button {
                        model.updateQuery("")
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
            .onChange(of: model.searchFocusToken) { focused = true }

            if model.query.isEmpty {
                historyList
            } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                ContentUnavailableView(
                    "再输入一个字", systemImage: "character.cursor.ibeam",
                    description: Text("单个字在中文里会命中几乎每一页"))
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
                            model.showSearch = false
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
