import SwiftUI
import ContentKit

/// 单个 block 的渲染。表格与图片是简化实现，见文件末尾说明。
struct BlockView: View {
    let block: Block
    var highlight: String?
    var availableWidth: CGFloat = Reading.measure

    @Environment(\.readingTheme) private var theme

    var body: some View {
        switch block.type {
        case "h":
            heading
        case "p", "dt":
            ParagraphView(
                runs: block.runsOrEmpty, fontSize: Reading.bodySize,
                highlight: highlight, availableWidth: availableWidth
            )
            .padding(.bottom, Reading.bodySize * 0.95)
        case "dd":
            JustifiedText(
                runs: block.runsOrEmpty, fontSize: Reading.bodySize,
                highlight: highlight, theme: theme
            )
            .padding(.leading, 24)
            .padding(.bottom, Reading.bodySize * 0.6)
        case "list":
            ListBlockView(block: block, highlight: highlight, availableWidth: availableWidth)
        case "table":
            TableBlockView(block: block, availableWidth: availableWidth)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(block.blocksOrEmpty.enumerated()), id: \.offset) { _, inner in
                    BlockView(block: inner, highlight: highlight, availableWidth: availableWidth)
                }
            }
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
        guard let hex = SourceStyle.headingColorHex(level: block.level ?? 2),
            let rgb = RGB(hexOrRGB: hex)
        else { return nil }
        return theme.adjusted(rgb)
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
                block.runsOrEmpty, size: Reading.bodySize * scale,
                bold: weight == .bold, highlight: highlight,
                theme: theme, defaultColor: headingDefaultColor)
        )
        .lineSpacing(Reading.bodySize * scale * 0.4)
        .padding(.top, level <= 2 ? 26 : 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 列表

/// 段落：把连续的文本 run 合成一段，图片单独成块。
/// 找不到的图片直接不渲染——离线包里本来就没有的那些不管（见 0016）。
private struct ParagraphView: View {
    let runs: [Run]
    let fontSize: CGFloat
    var highlight: String?
    var availableWidth: CGFloat

    @Environment(\.readingTheme) private var theme

    private enum Piece {
        case text([Run])
        case image(Run)
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var buffer: [Run] = []
        for run in runs {
            if run.img != nil {
                if !buffer.isEmpty {
                    result.append(.text(buffer))
                    buffer = []
                }
                result.append(.image(run))
            } else {
                buffer.append(run)
            }
        }
        if !buffer.isEmpty { result.append(.text(buffer)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .text(let runs):
                    JustifiedText(runs: runs, fontSize: fontSize, highlight: highlight, theme: theme)
                case .image(let run):
                    ContentImageView(run: run, maxWidth: availableWidth)
                }
            }
        }
    }
}

/// 从 App 包里按拍平后的文件名取图。缺图返回空视图，不留占位。
struct ContentImageView: View {
    let run: Run
    var maxWidth: CGFloat

    var body: some View {
        #if canImport(UIKit)
            if let image = Self.load(run.img) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 4))
            }
        #else
            if let image = Self.load(run.img) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 4))
            }
        #endif
    }

    /// 语料内路径在打包时被拍平成 `目录_文件`，两端用同一个变换。
    static func bundleName(for path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }

    #if canImport(UIKit)
        static func load(_ path: String?) -> UIImage? {
            guard let path else { return nil }
            guard let url = Bundle.main.url(forResource: bundleName(for: path), withExtension: nil)
            else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    #else
        static func load(_ path: String?) -> NSImage? {
            guard let path else { return nil }
            guard let url = Bundle.main.url(forResource: bundleName(for: path), withExtension: nil)
            else { return nil }
            return NSImage(contentsOf: url)
        }
    #endif
}

private struct ListBlockView: View {
    let block: Block
    var highlight: String?
    var availableWidth: CGFloat = Reading.measure

    @Environment(\.readingTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(index))
                        .font(.custom("Songti SC", size: Reading.bodySize))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.runs.isEmpty {
                            Text(
                                AttributedText.make(
                                    item.runs, size: Reading.bodySize,
                                    highlight: highlight)
                            )
                            .lineSpacing(Reading.lineSpacing)
                        }
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, inner in
                            BlockView(block: inner, highlight: highlight, availableWidth: availableWidth)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, Reading.bodySize * 0.95)
    }

    private func marker(_ index: Int) -> String {
        (block.ordered == true) ? "\(index + 1)." : "•"
    }
}

// MARK: - 表格

/// 表格：列宽按内容估算、自然宽度不铺满、支持 colspan、行级懒加载。
/// rowspan 不支持（全库 40 个表），合并格渲染在首行，被覆盖的格子留空。
private struct TableBlockView: View {
    let block: Block
    var availableWidth: CGFloat

    @Environment(\.readingTheme) private var theme

    private var columnCount: Int { TableLayoutCalculator.columnCount(block) }

    private var fontSize: CGFloat {
        switch columnCount {
        case ...2: Reading.bodySize
        case 3...4: 16
        default: 13
        }
    }

    private var widths: [CGFloat] {
        TableLayoutCalculator.widths(
            block, fontSize: fontSize,
            available: min(availableWidth, Reading.measure) - TableLayoutCalculator.horizontalPadding)
    }

    private var totalWidth: CGFloat { widths.reduce(0, +) }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array((block.rows ?? []).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, at: index)
                    }
                }
                .frame(width: totalWidth, alignment: .leading)
                .background(rowColor(row))
            }
        }
        .overlay(Rectangle().stroke(theme.border, lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: 4))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .padding(.bottom, 12)
    }

    private func rowColor(_ row: ContentKit.TableRow) -> Color {
        guard let hex = row.bg else { return .clear }
        return background(from: hex)
    }

    private func background(from hex: String) -> Color {
        guard let rgb = RGB(hexOrRGB: hex) else { return .clear }
        return theme.adjustedBackground(rgb)
    }

    private func cellBackground(_ cell: TableCell) -> Color {
        guard let hex = cell.bg else { return .clear }
        return background(from: hex)
    }

    private func width(at index: Int, span: Int) -> CGFloat {
        let upper = min(widths.count, index + span)
        guard index < upper else { return widths.last ?? 0 }
        return widths[index..<upper].reduce(0, +)
    }

    private func cellView(_ cell: TableCell, at index: Int) -> some View {
        let span = max(1, cell.colspan ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(cell.blocks.enumerated()), id: \.offset) { _, inner in
                Text(
                    AttributedText.make(
                        inner.runsOrEmpty, size: fontSize, bold: cell.header == true, theme: theme)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: width(at: index, span: span), alignment: .topLeading)
        .background(Color(hex: cell.bg ?? "") ?? .clear)
        .overlay(Rectangle().stroke(theme.border, lineWidth: 0.5))
    }
}

// MARK: - 富文本

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
            let weight: Font.Weight = (bold || run.b == 1) ? .bold : .regular
            var font = Font.custom("Songti SC", size: size).weight(weight)
            if run.i == 1 { font = font.italic() }
            let color: Color = resolvedColor(
                for: run, theme: theme, defaultColor: defaultColor)

            for (segment, hit) in split(text, by: highlight) {
                var piece = AttributedString(segment)
                piece.font = font
                piece.foregroundColor = color
                if hit { piece.backgroundColor = Color.accentColor.opacity(0.22) }
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

extension Color {
    /// 接受 `#rrggbb` 或 `rrggbb`。
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1)
    }
}
