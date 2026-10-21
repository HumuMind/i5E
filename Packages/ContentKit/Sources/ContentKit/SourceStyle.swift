import Foundation

/// 上游 `style.css` 里用标签表达的颜色规则。
///
/// 我们的数据只保留**内联**颜色，靠样式表来的这一层在阅读模式里丢失了：
/// 标题变黑、术语不再绿、法术名不再紫。这里把规则固化下来，供渲染时补默认色。
///
/// 来源：`DND5e_chm/style.css`
/// - `h1,h2,h3 { color:#800000 }`
/// - `h4 { color:#704cd9 }`
/// - `h6 { color:#0f5cbc }`
/// - `U { color:#008000 }`（术语）
/// - `U EM, U I { color:#704CD9 }`（法术）
/// - `B U, U B, STRONG U, U STRONG { color:#ee3300 }`（怪物）
public enum SourceStyle {

    public static func headingColorHex(level: Int) -> String? {
        switch level {
        case 1...3: "#800000"
        case 4: "#704cd9"
        case 6: "#0f5cbc"
        default: nil
        }
    }

    /// 下划线是上游的语义标记：术语 / 法术 / 怪物，靠是否同时斜体或加粗区分。
    public static func inlineColorHex(underlined: Bool, italic: Bool, bold: Bool) -> String? {
        guard underlined else { return nil }
        if bold { return "#ee3300" }
        if italic { return "#704cd9" }
        return "#008000"
    }
}
