import ContentKit
import SwiftUI

// MARK: - 目录树

struct TOCTree: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let nodes: [TOCNode]

    private var sections: [TOCSection] { TOCSectionBuilder.build(from: nodes) }

    /// 当前页在目录里对应的节点（最深的一层）。页不在目录里时为 nil。
    private var currentID: String? {
        guard let path = model.routes.last?.path else { return nil }
        return model.ancestorNodes[path]?.last
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !model.bookmarks.isEmpty {
                    Section("书签") {
                        ForEach(model.bookmarks) { bookmark in
                            Button {
                                model.show(
                                    AppModel.Route(path: bookmark.path, offset: bookmark.offset))
                                model.closeDrawer()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title).lineLimit(1)
                                    Text(bookmark.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .rowHitArea()
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
            // 跳转/翻页/启动恢复之后，把当前条目滚到可见处——否则目录还停在旧位置
            .task(id: currentID) {
                guard let currentID else { return }
                // 祖先展开和行布局各要一帧；等两帧再滚，否则会滚到空处
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(currentID, anchor: .center)
                }
            }
        }
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
            set: { model.setExpanded(node.id, $0) })
    }

    var body: some View {
        if node.c.isEmpty {
            Button {
                guard let path = node.u else { return }
                model.show(AppModel.Route(path: path))
                model.closeDrawer()
            } label: {
                rowLabel(systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .disabled(node.u == nil)
            .id(node.id)
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
                    model.closeDrawer()
                } label: {
                    rowLabel(systemImage: "book.closed")
                }
                .buttonStyle(.plain)
            }
            .id(node.id)
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
        .rowHitArea()
    }
}
