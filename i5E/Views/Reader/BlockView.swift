import ContentKit
import SwiftUI

struct BlockView: View {
    @Environment(\.readingMetrics) private var metrics
    let block: Block
    /// 祖先容器的 class（`stat-block` 等），用于按源页样式渲染内部元素。
    var ancestors: Set<String> = []
    /// 浮动图已经在外面并排渲染时，段落里不再重复画一次
    var skipFloatedImage = false
    var highlight: String?
    var availableWidth: CGFloat = ReadingMetrics.standard.measure

    @Environment(\.readingTheme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        switch block.type {
        case "h":
            heading
        case "p", "dt":
            ParagraphView(
                runs: block.runsOrEmpty, fontSize: metrics.bodySize,
                alignment: Self.textAlignment(block.al),
                skipFloatedImage: skipFloatedImage,
                highlight: highlight, availableWidth: availableWidth
            )
            .padding(.bottom, metrics.bodySize * 0.95)
        case "dd":
            BodyText(
                runs: block.runsOrEmpty, fontSize: metrics.bodySize,
                highlight: highlight, theme: theme
            )
            .padding(.leading, 24)
            .padding(.bottom, metrics.bodySize * 0.6)
        case "list":
            ListBlockView(block: block, highlight: highlight, availableWidth: availableWidth)
        case "table":
            TableBlockView(block: block, ancestors: ancestors, availableWidth: availableWidth)
        case "quote":
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(.quaternary).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(block.blocksOrEmpty.enumerated()), id: \.offset) { _, inner in
                        BlockView(block: inner, highlight: highlight, availableWidth: availableWidth)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 12)
        case "div":
            container
        case "pre":
            Text(block.text ?? "")
                .font(.system(size: 14, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
                .padding(.bottom, 16)
        case "hr":
            Divider().padding(.vertical, 20)
        default:
            EmptyView()
        }
    }

    /// 上游 `style.css` 给标题规定的颜色。数据里只有内联色，
    /// 靠样式表来的这一层要在这里补上（见 0017 补记）。
    private var headingDefaultColor: Color? {
        // 页面内联样式里对标题颜色的覆盖优先于全局规则
        if let hex = block.style?.c, let rgb = RGB(hexOrRGB: hex) {
            return theme.adjustedHeading(rgb)
        }
        // 数据块里的 h5/h6 在源页是暗红（stat-block.css），不按普通标题的规则
        if ClassStyle.isStatBlockHeading(ancestors: ancestors), (block.level ?? 0) >= 5 {
            return RGB(hexOrRGB: "#800000").map { theme.adjusted($0) }
        }
        guard let hex = SourceStyle.headingColorHex(level: block.level ?? 2),
            let rgb = RGB(hexOrRGB: hex)
        else { return nil }
        return theme.adjustedHeading(rgb)
    }

    /// 带样式的容器（stat-block / little-paper / HT）。没有已知 class 时只做纵向堆叠。
    private var container: some View {
        let childAncestors = ancestors.union(block.cls ?? [])
        let style = ClassStyle.container(block.cls ?? [])
        // 子块要按容器的内宽排版，否则表格会撑出边框被裁掉
        let innerWidth: CGFloat = {
            guard let style else { return availableWidth }
            let capped = min(availableWidth, style.maxWidth ?? availableWidth)
            let inset = capped * style.marginFraction * 2
            let horizontal = min(style.paddingHorizontal, (capped - inset) * 0.15)
            return max(120, capped - inset - horizontal * 2)
        }()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(block.blocksOrEmpty.enumerated()), id: \.offset) { _, inner in
                BlockView(
                    block: inner, ancestors: childAncestors, highlight: highlight,
                    availableWidth: innerWidth)
            }
        }
        .padding(.top, style?.paddingTop ?? 0)
        .padding(.bottom, style?.paddingTop ?? 0)
        .padding(.horizontal, horizontalPadding(style))
        .frame(maxWidth: containerMaxWidth(style), alignment: .leading)
        .background(containerFill(style), in: .rect(cornerRadius: 2))
        .overlay { containerBorder(style) }
        .padding(.bottom, style == nil ? 0 : 14)
    }

    private func horizontalPadding(_ style: ClassStyle.Container?) -> CGFloat {
        guard let style else { return 0 }
        let capped = min(availableWidth, style.maxWidth ?? availableWidth)
        return min(style.paddingHorizontal, capped * 0.15)
    }

    private func containerMaxWidth(_ style: ClassStyle.Container?) -> CGFloat? {
        guard let style else { return nil }
        let capped = min(availableWidth, style.maxWidth ?? availableWidth)
        return capped * (1 - style.marginFraction * 2)
    }

    /// 标题下划线：优先用页面 CSS 里声明的颜色，其次数据块标题的暗红。
    @ViewBuilder
    private var headingUnderline: some View {
        if let border = block.style?.bd {
            let color =
                (border == "1" ? nil : RGB(hexOrRGB: border).map { theme.adjusted($0) }) ?? theme.border
            Rectangle()
                .fill(color)
                .frame(height: 1)
                .padding(.top, 4)
        } else if ClassStyle.isStatBlockHeading(ancestors: ancestors), (block.level ?? 0) >= 5 {
            Rectangle()
                .fill(RGB(hexOrRGB: "#800000").map { theme.adjusted($0) } ?? theme.accent)
                .frame(height: 1)
                .padding(.top, 2)
        }
    }

    private func containerFill(_ style: ClassStyle.Container?) -> Color {
        guard let style else { return .clear }
        // 深色下改用阅读面色：源页的浅色底在深色主题里会刺眼
        return theme.isDark ? theme.surface : Color(themeHex: style.background)
    }

    @ViewBuilder
    private func containerBorder(_ style: ClassStyle.Container?) -> some View {
        if let style {
            let color = Color(themeHex: style.border)
            if style.topBorderOnly {
                VStack(spacing: 0) {
                    Rectangle().fill(color).frame(height: style.borderWidth)
                    Spacer(minLength: 0)
                }
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color, lineWidth: style.borderWidth / 2)
            }
        }
    }

    /// 源页的 align 属性 → 原生对齐方式。
    static func textAlignment(_ al: String?) -> NSTextAlignment {
        switch al?.lowercased() {
        case "r", "right": .right
        case "c", "center": .center
        case "j", "justify": .justified
        default: .natural
        }
    }

    private var heading: some View {
        let level = block.level ?? 2
        let (scale, weight): (CGFloat, Font.Weight) =
            switch level {
            case 1: (1.6, .bold)
            case 2: (1.35, .bold)
            case 3: (1.2, .semibold)
            case 4: (1.25, .semibold)  // 上游用 h4 做法术/怪物条目标题
            case 5: (1.1, .semibold)
            default: (1.0, .semibold)
            }
        return Text(
            AttributedText.make(
                block.runsOrEmpty, size: metrics.bodySize * scale,
                bold: weight == .bold || block.style?.b == 1, highlight: highlight,
                theme: theme, defaultColor: headingDefaultColor, largeText: true)
        )
        .lineSpacing(metrics.bodySize * scale * 0.4)
        .padding(.top, level <= 2 ? 26 : 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 列表

/// 段落：把连续的文本 run 合成一段，图片单独成块。
/// 找不到的图片直接不渲染——离线包里本来就没有的那些不管（见 0016）。
