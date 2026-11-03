import ContentKit
import SwiftUI

// MARK: - 浮动按钮

struct FloatingBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showDrawer: Bool
    @Binding var showSettings: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    /// Mac 上目录常驻左侧，没有抽屉，也就不需要"目录"按钮（见 0050）。
    var showsTOCButton = true

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsTOCButton {
                button("list.bullet", label: "目录") {
                    showDrawer.toggle()
                }
            }
            button("magnifyingglass", label: "搜索") {
                model.focusSearch()
            }
            // 始终显示：不可用时只变淡，避免按钮忽隐忽现
            button("chevron.backward", label: "返回", enabled: canGoBack) {
                model.goBack()
            }
            button("chevron.forward", label: "前进", enabled: canGoForward) {
                model.goForward()
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canGoForward)
    }

    private func button(
        _ systemName: String, label: String, enabled: Bool = true,
        action: @escaping () -> Void
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// 居中卡片式浮层：点背景关闭。macOS 的 sheet 不支持点外部关闭，
/// 搜索与设置都改用它，与抽屉的行为保持一致。
