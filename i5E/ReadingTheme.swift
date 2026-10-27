import ContentKit
import SwiftUI

/// 阅读区配色，取自上游 WebHelp 模板的 CSS 变量（见 0017）。
struct ReadingTheme: Sendable {
    let isDark: Bool
    let background: Color
    let surface: Color
    let text: Color
    let muted: Color
    let border: Color
    let accent: Color
    let link: Color
    /// 表格隔行底色（源 HTML 没有，按网页版的观感加）
    let zebra: Color

    static let light = ReadingTheme(
        isDark: false,
        background: Color(themeHex: "#f4f5f7"),
        surface: Color(themeHex: "#ffffff"),
        text: Color(themeHex: "#242629"),
        muted: Color(themeHex: "#666a70"),
        border: Color(themeHex: "#e0e2e5"),
        accent: Color(themeHex: "#991b1b"),
        link: Color(themeHex: "#1d5fa7"),
        zebra: Color(themeHex: "#f2f3f5"))

    static let dark = ReadingTheme(
        isDark: true,
        background: Color(themeHex: "#111315"),
        surface: Color(themeHex: "#17191c"),
        text: Color(themeHex: "#e7e9ec"),
        muted: Color(themeHex: "#a8adb4"),
        border: Color(themeHex: "#34383e"),
        accent: Color(themeHex: "#e16d6d"),
        link: Color(themeHex: "#72a7e4"),
        zebra: Color(themeHex: "#2a2d33"))

    static func resolve(_ scheme: ColorScheme) -> ReadingTheme {
        scheme == .dark ? .dark : .light
    }

    /// 对比度计算用的底色。
    var surfaceRGB: RGB {
        RGB(hexOrRGB: isDark ? "#17191c" : "#ffffff") ?? RGB(r: 1, g: 1, b: 1)
    }

    /// 把源页颜色修到在当前底色上可读。
    func adjusted(_ source: RGB, minimum: Double = 4.5) -> Color {
        Color(rgb: Contrast.repair(source, on: surfaceRGB, minimum: minimum))
    }

    /// 标题按 WCAG 的"大字"标准放宽到 3:1。
    ///
    /// 按正文的 4.5:1 处理会把源页的亮橙 `#ff8000` 压成褐色，
    /// 而 18pt 以上的文字 3:1 就够了。
    func adjustedHeading(_ source: RGB) -> Color {
        adjusted(source, minimum: 3.0)
    }

    /// 表格底色：深色下压暗、保留色相。
    func adjustedBackground(_ source: RGB) -> Color {
        isDark ? Color(rgb: Contrast.darken(source, toward: surfaceRGB)) : Color(rgb: source)
    }
}

private struct ReadingThemeKey: EnvironmentKey {
    static let defaultValue = ReadingTheme.light
}

private struct UsesStyleSheetKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// 页面是否引用了上游 `style.css`（决定标题的默认颜色）。
    var usesStyleSheet: Bool {
        get { self[UsesStyleSheetKey.self] }
        set { self[UsesStyleSheetKey.self] = newValue }
    }

    var readingTheme: ReadingTheme {
        get { self[ReadingThemeKey.self] }
        set { self[ReadingThemeKey.self] = newValue }
    }
}

extension Color {
    /// 允许直接写 `#rrggbb` 的便捷构造（配色表里全是字面量）。
    init(themeHex hex: String) {
        self = Color(hex: hex) ?? .black
    }

    init(rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}
