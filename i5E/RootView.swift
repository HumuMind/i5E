import ContentKit
import SwiftUI

/// 阅读界面。
///
/// iPhone 与 iPad：全屏内容 + 浮动按钮 + 抽屉式目录（见 0035）。
/// Mac：窗口本身够宽，目录直接常驻左侧，既没有"目录"按钮也没有抽屉（见 0050）。
struct RootView: View {
    var body: some View {
        Group {
            #if os(macOS)
                MacRoot()
            #else
                CompactRoot()
            #endif
        }
        .modifier(Panels())
    }
}

// MARK: - 两个平台的骨架

/// iPhone 与 iPad：内容铺满，目录从左侧滑出。
private struct CompactRoot: View {
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
    }
}

#if os(macOS)
    /// Mac：左侧常驻目录，右侧阅读区。两者之间只隔一条细线，不分窗、不再折叠。
    private struct MacRoot: View {
        @Environment(AppModel.self) private var model
        @Environment(\.colorScheme) private var colorScheme

        private var theme: ReadingTheme { .resolve(colorScheme) }

        var body: some View {
            @Bindable var model = model
            HStack(spacing: 0) {
                SidebarColumn()
                Rectangle()
                    .fill(theme.border)
                    .frame(width: 1)
                ZStack(alignment: .top) {
                    ReaderContent()
                        .hideNavigationChrome()
                    FloatingBar(
                        showDrawer: $model.showDrawer, showSettings: $model.showSettings,
                        canGoBack: model.routes.count > 1, showsTOCButton: false
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
            }
            // 再窄就压到版心了；宽度下限给目录留 300，正文留 420
            .frame(minWidth: MacLayout.minWindowWidth, minHeight: 480)
        }
    }
#endif

// MARK: - 居中浮层

/// 查找与设置：卡片式浮层，覆盖整个窗口。
private struct Panels: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
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

// MARK: - 页面区域

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
    private var hint: String {
        #if os(macOS)
            "在左侧目录里选一页开始读"
        #else
            "左上角的按钮打开目录，也可以在里面搜索"
        #endif
    }

    var body: some View {
        ContentUnavailableView(
            "选一页开始读", systemImage: "book", description: Text(hint))
    }
}
