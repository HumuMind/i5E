import SwiftUI
import ContentKit

#if canImport(UIKit)
    import UIKit

    /// 正文段落。
    ///
    /// 用 UIKit 渲染而不是 SwiftUI 的 `Text`，是为了拿到行距与字体的精确控制。
    /// 对齐方式为左对齐（0036）：中文与英文/数字混排时，两端对齐会把可拉伸的
    /// 空格撑开，字距变得很难看。
    struct BodyText: View {
        let runs: [Run]
        let fontSize: CGFloat
        /// 源页的 align 属性（l/c/r/justify）
        var alignment: NSTextAlignment = .natural
        var highlight: String?
        var theme: ReadingTheme = .light
        var onOpenLink: (@MainActor (URL) -> Void)?

        @Environment(\.mentionLevel) private var mentionLevel

        var body: some View {
            BodyLabel(
                attributed: Self.attributed(
                    runs: runs, fontSize: fontSize, alignment: alignment,
                    highlight: highlight, theme: theme, mentionLevel: mentionLevel),
                onOpenLink: onOpenLink)
        }

        static func attributed(
            runs: [Run], fontSize: CGFloat, alignment: NSTextAlignment = .natural,
            highlight: String? = nil, theme: ReadingTheme = .light,
            mentionLevel: Int = 3
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = fontSize * (Reading.lineHeightMultiple - 1)
            // 中文行禁则：把不能出现在行首的标点挤回上一行
            paragraph.lineBreakStrategy = .pushOut

            let result = NSMutableAttributedString()
            for run in runs {
                guard let text = run.t, !text.isEmpty else { continue }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font(for: run, size: fontSize),
                    .paragraphStyle: paragraph,
                    .foregroundColor: color(for: run, theme: theme),
                ]
                // 自动链接（0051）：正文色 + 淡下划线，不抢作者的链接
                let mention = run.m.map { $0 <= mentionLevel } ?? false
                if run.m != nil {
                    if mention {
                        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        attributes[.underlineColor] = UIColor(theme.link).withAlphaComponent(0.4)
                    }
                } else if run.u == 1 || run.href != nil {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                // 上标/下标：字号缩到 72%，并相对基线升降
                if run.sup == 1 || run.sub == 1 {
                    attributes[.font] = font(for: run, size: fontSize * 0.72)
                    attributes[.baselineOffset] = run.sup == 1 ? fontSize * 0.38 : -fontSize * 0.18
                }
                if run.s == 1 { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }

                for (segment, hit) in AttributedText.split(text, by: highlight) {
                    var pieceAttributes = attributes
                    if hit {
                        pieceAttributes[.backgroundColor] = UIColor.tintColor.withAlphaComponent(0.22)
                    }
                    // 关掉自动链接后，这些 run 就当普通文字
                    if let href = run.href, let url = URL(string: href),
                        !(run.m != nil && !mention)
                    {
                        pieceAttributes[.link] = url
                    }
                    result.append(NSAttributedString(string: segment, attributes: pieceAttributes))
                }
            }
            return result
        }

        private static func font(for run: Run, size: CGFloat) -> UIFont {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.b == 1 { traits.insert(.traitBold) }
            if run.i == 1 { traits.insert(.traitItalic) }

            // 与源页一致用无衬线（系统字体在中文下是苹方）
            let base = UIFont.systemFont(ofSize: size)
            guard !traits.isEmpty,
                let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        private static func color(for run: Run, theme: ReadingTheme) -> UIColor {
            UIColor(AttributedText.resolvedColor(for: run, theme: theme))
        }
    }

#endif

#if canImport(UIKit)

    /// 用 UITextView 而不是 UILabel：正文里的链接要能点。
    private struct BodyLabel: UIViewRepresentable {
        let attributed: NSAttributedString
        var onOpenLink: (@MainActor (URL) -> Void)?

        func makeCoordinator() -> Coordinator { Coordinator(onOpenLink: onOpenLink) }

        func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isScrollEnabled = false
            // 不选中：长按不再出现选择手柄。链接改由手势命中，见 Coordinator.handleTap
            view.isSelectable = false
            view.backgroundColor = .clear
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.dataDetectorTypes = []
            // 链接的颜色与下划线由富文本自己决定（自动链接是淡下划线，不是链接蓝）
            view.linkTextAttributes = [:]
            view.delegate = context.coordinator
            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            view.addGestureRecognizer(tap)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return view
        }

        func updateUIView(_ view: UITextView, context: Context) {
            context.coordinator.onOpenLink = onOpenLink
            view.attributedText = attributed
            // 字号变化后必须让 UIKit 重新算高度，否则 SwiftUI 会沿用旧尺寸
            view.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize, uiView: UITextView, context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0 else { return nil }
            let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: ceil(size.height))
        }

        final class Coordinator: NSObject, UITextViewDelegate {
            var onOpenLink: (@MainActor (URL) -> Void)?

            init(onOpenLink: (@MainActor (URL) -> Void)?) {
                self.onOpenLink = onOpenLink
            }

            func textView(
                _ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                interaction: UITextItemInteraction
            ) -> Bool {
                let handler = onOpenLink
                MainActor.assumeIsolated { handler?(URL) }
                return false
            }

            /// 正文不可选中，链接靠手势命中：先算点击处的字符，再看那里有没有 .link。
            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let textView = gesture.view as? UITextView else { return }
                let point = gesture.location(in: textView)
                let index = textView.layoutManager.characterIndex(
                    for: point, in: textView.textContainer,
                    fractionOfDistanceBetweenInsertionPoints: nil)
                let storage = textView.textStorage
                guard index < storage.length else { return }
                guard let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL
                else { return }
                let handler = onOpenLink
                MainActor.assumeIsolated { handler?(url) }
            }
        }
    }
#else

    /// macOS 上没有 UIKit；先用 SwiftUI 的 Text，两端对齐在 Mac 端待补（可用 NSTextView）。
    struct BodyText: View {
        let runs: [Run]
        let fontSize: CGFloat
        var alignment: NSTextAlignment = .natural
        var skipFloatedImage = false
        var highlight: String?
        var theme: ReadingTheme = .light
        var onOpenLink: (@MainActor (URL) -> Void)?

        @Environment(\.mentionLevel) private var mentionLevel

        var body: some View {
            Text(
                AttributedText.make(
                    runs, size: fontSize, highlight: highlight, theme: theme,
                    mentionLevel: mentionLevel)
            )
            .lineSpacing(Reading.lineSpacing)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }

        /// 短行在整行宽度里靠哪边放：只有 multilineTextAlignment 不够，
        /// frame 的对齐也要跟着改，否则居中段落仍会贴在左边。
        private var frameAlignment: Alignment {
            switch alignment {
            case .right: .trailing
            case .center: .center
            default: .leading
            }
        }

        private var textAlignment: TextAlignment {
            switch alignment {
            case .right: .trailing
            case .center: .center
            default: .leading
            }
        }
    }

#endif
