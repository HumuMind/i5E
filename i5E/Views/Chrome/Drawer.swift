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
            .background(theme.surface.ignoresSafeArea(edges: .vertical))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 2)
        }
    }
}

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
