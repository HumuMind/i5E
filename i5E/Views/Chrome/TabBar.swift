import SwiftUI

/// 标签页条。Mac 上放在窗口工具栏里，iPad/iPhone 上放在内容顶部。
///
/// 每个 tab 的页面、返回/前进历史和滚动位置都由 `AppModel` 单独保存；
/// 这里只负责切换、新建和关闭。
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.tabs) { tab in
                            chip(tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onAppear { scrollToActive(proxy, animated: false) }
                .onChange(of: model.activeTabID) { _, _ in
                    scrollToActive(proxy, animated: true)
                }
            }

            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建标签页")
            .accessibilityIdentifier("tab.new")
            .padding(.trailing, 6)
        }
        .frame(height: 34)
        .background {
            // 铺到状态栏下面，否则深色主题里顶部会露出系统底色
            theme.surface.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.border)
        }
    }

    // MARK: - 单个标签页

    private func chip(_ tab: AppModel.Tab) -> some View {
        let isActive = tab.id == model.activeTabID
        let canClose = model.tabs.count > 1
        return Button {
            model.selectTab(tab.id)
        } label: {
            HStack(spacing: 4) {
                Text(tab.title.isEmpty ? "新标签页" : tab.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? theme.text : theme.muted)
                    .lineLimit(1)
                // 给覆盖在上面的关闭按钮留位置
                if canClose { Color.clear.frame(width: 14, height: 14) }
            }
            .padding(.leading, 10)
            .padding(.trailing, canClose ? 6 : 10)
            .padding(.vertical, 5)
            .frame(minWidth: 100, maxWidth: 200, alignment: .leading)
            .background(
                isActive ? theme.background : Color.clear,
                in: .rect(cornerRadius: 6)
            )
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.item.\(tab.id.uuidString)")
        .overlay(alignment: .trailing) {
            if canClose {
                Button {
                    model.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
                .accessibilityLabel("关闭标签页")
                .accessibilityIdentifier("tab.close.\(tab.id.uuidString)")
            }
        }
    }

    private func scrollToActive(_ proxy: ScrollViewProxy, animated: Bool) {
        guard model.tabs.contains(where: { $0.id == model.activeTabID }) else { return }
        if animated {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(model.activeTabID, anchor: .center)
            }
        } else {
            proxy.scrollTo(model.activeTabID, anchor: .center)
        }
    }
}
