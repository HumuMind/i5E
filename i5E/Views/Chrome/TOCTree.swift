import ContentKit
import SwiftUI

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
                            model.showDrawer = false
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
        .scrollContentBackground(.hidden)
    }
}

struct NodeRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let node: TOCNode
    let depth: Int

    private var highlight: Color { ReadingTheme.resolve(colorScheme).accent }

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
                model.showDrawer = false
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
                    model.showDrawer = false
                } label: {
                    rowLabel(systemImage: "book.closed")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 当前正在读的页面
    private var isCurrent: Bool {
        guard let url = node.u else { return false }
        let path = url.split(separator: "#").first.map(String.init) ?? url
        return model.routes.last?.path == path
    }

    private func rowLabel(systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(isCurrent ? highlight : .secondary)
            Text(node.t)
                .lineLimit(1)
                .foregroundStyle(isCurrent ? highlight : .primary)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .padding(.leading, CGFloat(depth) * 8 + (isCurrent ? 4 : 0))
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule().fill(highlight).frame(width: 3).padding(.vertical, 1)
            }
        }
        .contentShape(Rectangle())
    }
}
