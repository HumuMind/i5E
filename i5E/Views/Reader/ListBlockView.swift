import ContentKit
import SwiftUI

struct ListBlockView: View {
    @Environment(\.readingMetrics) private var metrics
    let block: Block
    /// 祖先容器的 class（`stat-block` 等），用于按源页样式渲染内部元素。
    var ancestors: Set<String> = []
    /// 浮动图已经在外面并排渲染时，段落里不再重复画一次
    var skipFloatedImage = false
    var highlight: String?
    var availableWidth: CGFloat = ReadingMetrics.standard.measure

    @Environment(\.readingTheme) private var theme
    @Environment(\.mentionLevel) private var mentionLevel
    @Environment(\.mentionUnderline) private var mentionUnderline

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(index))
                        .font(.system(size: metrics.bodySize))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.runs.isEmpty {
                            Text(
                                AttributedText.make(
                                    item.runs, size: metrics.bodySize,
                                    highlight: highlight, theme: theme,
                                    mentionLevel: mentionLevel,
                                    mentionUnderline: mentionUnderline)
                            )
                            .lineSpacing(metrics.lineSpacing)
                        }
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, inner in
                            BlockView(block: inner, highlight: highlight, availableWidth: availableWidth)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, metrics.bodySize * 0.95)
    }

    private func marker(_ index: Int) -> String {
        (block.ordered == true) ? "\(index + 1)." : "•"
    }
}

// MARK: - 表格

/// 表格：列宽按内容估算、自然宽度不铺满、行级懒加载。
/// colspan / rowspan 由 `TableGrid` 落位：合并格在首行渲染，被覆盖的格子留空（见 0015 补记）。
