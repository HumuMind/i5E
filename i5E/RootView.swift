import SwiftUI
import ContentKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            DetailView()
        }
    }
}

// MARK: - 侧栏：目录 / 搜索

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query)
            Divider()
            content
        }
        .navigationTitle("5E 不全书")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("打开内容库…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "内容库打不开", systemImage: "exclamationmark.triangle",
                description: Text(message))
        case .ready:
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TOCTree(nodes: model.toc?.nodes ?? [])
            } else {
                SearchResultsView()
            }
        }
    }
}

private struct SearchField: View {
    @Environment(AppModel.self) private var model
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索正文", text: $text)
                .textFieldStyle(.plain)
                #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if model.isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: text) { _, newValue in
            model.updateQuery(newValue)
        }
    }
}

struct TOCTree: View {
    let nodes: [TOCNode]

    private var sections: [TOCSection] { TOCSectionBuilder.build(from: nodes) }

    var body: some View {
        List {
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
    @State private var expanded = false

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
        } else {
            DisclosureGroup(isExpanded: $expanded) {
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
                        Text(hit.title.isEmpty ? hit.path : hit.title)
                            .font(.headline)
                        Text(hit.snippet)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(hit.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 详情

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.routes) {
            ContentUnavailableView(
                "选一页开始读", systemImage: "book",
                description: Text("左侧目录里挑一章，或者搜索正文")
            )
            .navigationDestination(for: AppModel.Route.self) { route in
                PageScreen(route: route)
            }
        }
    }
}
