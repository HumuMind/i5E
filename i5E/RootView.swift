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
            ReaderContent()
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
        .overlay {
            if model.showDrawer {
                DrawerBackdrop()
                    .transition(.opacity)
                    .onTapGesture { model.showDrawer = false }
            }
        }
        .overlay(alignment: .leading) {
            if model.showDrawer {
                DrawerPanel()
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.showDrawer)
        #if os(macOS)
            // Esc 关抽屉（iOS 上没有这个命令）
            .onExitCommand { model.showDrawer = false }
        #endif
        .overlay {
            if model.showSearch {
                OverlayPanel(title: "查找", isPresented: $model.showSearch) {
                    SearchPanel()
                }
            }
        }
        .overlay {
            if model.showSettings {
                OverlayPanel(title: "设置", isPresented: $model.showSettings) {
                    SettingsView()
                }
            }
        }
    }
}

/// 隐藏系统导航栏。
///
/// 只在 iOS 上做：macOS 的窗口工具栏承载关闭/最小化/最大化三个按钮，
/// 隐藏之后窗口就没有标题栏了，只剩一条奇怪的色带。
private struct HideNavigationChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.toolbar(.hidden, for: .navigationBar)
        #else
            content
        #endif
    }
}

extension View {
    func hideNavigationChrome() -> some View {
        modifier(HideNavigationChrome())
    }
}

/// 页面区域。
///
/// iOS 用 NavigationStack，为的是右滑返回的手势与系统返回按钮。
/// macOS 不用：我们的路由是"替换 + 追加"混着来的，系统的"弹一层"语义对不上，
/// 点它的返回按钮会落到一个不该出现的页面。Mac 上用自己的浮动返回按钮。
private struct ReaderContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(macOS)
            if let route = model.routes.last {
                PageScreen(route: route)
                    .id(route)
            } else {
                loadingOrPlaceholder
            }
        #else
            @Bindable var model = model
            NavigationStack(path: $model.routes) {
                loadingOrPlaceholder
                    .navigationDestination(for: AppModel.Route.self) { route in
                        PageScreen(route: route)
                    }
            }
        #endif
    }

    /// 启动阶段的根视图。
    ///
    /// 三种状态：已有路由时留白（页面正在被推上来，不能露出底下的文字）、
    /// 加载中显示转圈、内容就绪但确实没有页面才显示占位。
    @ViewBuilder
    private var loadingOrPlaceholder: some View {
        if !model.routes.isEmpty {
            Color.clear
        } else if case .ready = model.phase {
            StartPlaceholder()
        } else if case .failed = model.phase {
            StartPlaceholder()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ReadingTheme.resolve(colorScheme).background)
        }
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
