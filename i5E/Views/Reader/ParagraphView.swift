import ContentKit
import SwiftUI

struct ParagraphView: View {
    @Environment(\.readingMetrics) private var metrics
    let runs: [Run]
    let fontSize: CGFloat
    var alignment: NSTextAlignment = .natural
    var skipFloatedImage = false
    var highlight: String?
    var availableWidth: CGFloat

    @Environment(\.readingTheme) private var theme
    @Environment(AppModel.self) private var app

    private enum Piece {
        case text([Run])
        case image(Run)
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var buffer: [Run] = []
        for run in runs {
            if run.img != nil {
                if skipFloatedImage, run.align == "right" { continue }
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

    /// 段落里带浮动图时，文字和图并排（近似源页的 `align=right` 浮动）。
    private var floatedImage: Run? {
        pieces.compactMap { piece in
            if case .image(let run) = piece, run.align == "right" { return run }
            return nil
        }.first
    }

    var body: some View {
        if let image = floatedImage {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                        if case .text(let runs) = piece {
                            BodyText(
                                runs: runs, fontSize: fontSize, alignment: alignment,
                                highlight: highlight, theme: theme,
                                onOpenLink: { app.handleLink($0) })
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ContentImageView(run: image, maxWidth: availableWidth * 0.42)
            }
        } else {
            plainBody
        }
    }

    private var plainBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .text(let runs):
                    BodyText(
                        runs: runs, fontSize: fontSize, alignment: alignment,
                        highlight: highlight, theme: theme,
                        onOpenLink: { app.handleLink($0) })
                case .image(let run):
                    ContentImageView(run: run, maxWidth: availableWidth)
                }
            }
        }
    }
}

/// 从 App 包里按拍平后的文件名取图。缺图返回空视图，不留占位。
