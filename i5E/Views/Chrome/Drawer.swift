import ContentKit
import SwiftUI

// MARK: - 抽屉

/// 抽屉的遮罩：淡入淡出，不跟着面板平移。
struct DrawerBackdrop: View {
    var body: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
    }
}

/// 抽屉面板：从左侧滑入。视觉方案取 1（与阅读面同色）。
struct DrawerPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                SidebarHeader()
                DrawerContent()
            }
            .frame(width: min(360, proxy.size.width * 0.88))
            .frame(maxHeight: .infinity)
            .background(theme.surface.ignoresSafeArea(edges: .vertical))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 2)
        }
    }
}

/// 抽屉与 Mac 常驻列共用的表头：书名 + 一条分隔线。
private struct SidebarHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("5E 不全书").font(.headline).foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            Divider().overlay(theme.border)
        }
    }
}

#if os(macOS)
    // MARK: - Mac 常驻目录列

    enum MacLayout {
        static let sidebarWidth: CGFloat = 300
        /// 目录 300 + 正文至少 420，再窄就会压到版心。
        static let minWindowWidth: CGFloat = 720
    }

    /// Mac 的目录列：不开合、不遮内容，一直待在左边。
    ///
    /// 内容与抽屉共用 `DrawerContent`，差别只在它不盖住正文，
    /// 所以也不来自阅读区顶部那 48pt 的让位——它自己占一列。
    struct SidebarColumn: View {
        @Environment(\.colorScheme) private var colorScheme

        private var theme: ReadingTheme { .resolve(colorScheme) }

        var body: some View {
            VStack(spacing: 0) {
                SidebarHeader()
                DrawerContent()
            }
            .frame(width: MacLayout.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(theme.surface)
        }
    }
#endif

struct DrawerContent: View {
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
