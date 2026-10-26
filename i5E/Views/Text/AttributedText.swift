import ContentKit
import SwiftUI

enum AttributedText {
    /// 把 run 序列转成 AttributedString。保留颜色、粗斜体、下划线。
    /// 字号一律用传入值——源页的绝对字号（8–22pt）在阅读模式里不采用。
    static func make(
        _ runs: [Run], size: CGFloat, bold: Bool = false,
        highlight: String? = nil, theme: ReadingTheme = .light,
        defaultColor: Color? = nil
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            guard let text = run.t, !text.isEmpty else { continue }
            // 自定义字体上直接加 .weight/.italic 在字体缺失时会被丢弃，
            // 因此同时写语义强调，由 SwiftUI 自己合成粗体与斜体。
            var intents: InlinePresentationIntent = []
            if bold || run.b == 1 { intents.insert(.stronglyEmphasized) }
            if run.i == 1 { intents.insert(.emphasized) }
            var font = Font.system(size: size)
            if bold || run.b == 1 { font = font.bold() }
            if run.i == 1 { font = font.italic() }
            let color: Color = resolvedColor(
                for: run, theme: theme, defaultColor: defaultColor)

            for (segment, hit) in split(text, by: highlight) {
                var piece = AttributedString(segment)
                piece.font = font
                piece.foregroundColor = color
                if hit { piece.backgroundColor = Color.accentColor.opacity(0.22) }
                if let href = run.href, let url = URL(string: href) { piece.link = url }
                if !intents.isEmpty { piece.inlinePresentationIntent = intents }
                if run.u == 1 { piece.underlineStyle = .single }
                if run.s == 1 { piece.strikethroughStyle = .single }
                result.append(piece)
            }
        }
        return result
    }

    /// 内联色优先；没有就按上游样式表的语义（术语/法术/怪物）补默认色；再退到正文色。
    static func resolvedColor(
        for run: Run, theme: ReadingTheme, defaultColor: Color? = nil
    ) -> Color {
        if let hex = run.c, let rgb = RGB(hexOrRGB: hex) {
            return theme.adjusted(rgb)
        }
        let semantic = SourceStyle.inlineColorHex(
            underlined: run.u == 1, italic: run.i == 1, bold: run.b == 1)
        if let semantic, let rgb = RGB(hexOrRGB: semantic) {
            return theme.adjusted(rgb)
        }
        return defaultColor ?? theme.text
    }

    /// 把文本按查询词切成 (片段, 是否命中)；没有高亮词时返回整段。
    static func split(_ text: String, by needle: String?) -> [(String, Bool)] {
        guard let needle, !needle.isEmpty else { return [(text, false)] }
        var parts: [(String, Bool)] = []
        var rest = Substring(text)
        while let range = rest.range(of: needle, options: .caseInsensitive) {
            if range.lowerBound > rest.startIndex {
                parts.append((String(rest[rest.startIndex..<range.lowerBound]), false))
            }
            parts.append((String(rest[range]), true))
            rest = rest[range.upperBound...]
        }
        if !rest.isEmpty { parts.append((String(rest), false)) }
        return parts
    }
}
