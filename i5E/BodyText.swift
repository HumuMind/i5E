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
        var highlight: String?
        var theme: ReadingTheme = .light
        var onOpenLink: (@MainActor (URL) -> Void)?

        var body: some View {
            BodyLabel(
                attributed: Self.attributed(
                    runs: runs, fontSize: fontSize, highlight: highlight, theme: theme),
                onOpenLink: onOpenLink)
        }

        static func attributed(
            runs: [Run], fontSize: CGFloat, highlight: String? = nil, theme: ReadingTheme = .light
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .natural
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
                if run.u == 1 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if run.s == 1 { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }

                for (segment, hit) in AttributedText.split(text, by: highlight) {
                    var pieceAttributes = attributes
                    if hit {
                        pieceAttributes[.backgroundColor] = UIColor.tintColor.withAlphaComponent(0.22)
                    }
                    if let href = run.href, let url = URL(string: href) {
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

            let base = UIFont(name: "Songti SC", size: size) ?? UIFont.systemFont(ofSize: size)
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
        var highlight: String?
        var theme: ReadingTheme = .light
        var onOpenLink: (@MainActor (URL) -> Void)?

        var body: some View {
            Text(AttributedText.make(runs, size: fontSize, highlight: highlight, theme: theme))
                .lineSpacing(Reading.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

#endif
