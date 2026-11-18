import SwiftUI
import ContentKit

#if canImport(AppKit)
    import AppKit
#endif

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
        @Environment(\.mentionUnderline) private var mentionUnderline

        @Environment(\.mentionLevel) private var mentionLevel

        var body: some View {
            BodyLabel(
                attributed: Self.attributed(
                    runs: runs, fontSize: fontSize, alignment: alignment,
                    highlight: highlight, theme: theme, mentionLevel: mentionLevel,
                    mentionUnderline: mentionUnderline),
                onOpenLink: onOpenLink)
        }

        static func attributed(
            runs: [Run], fontSize: CGFloat, alignment: NSTextAlignment = .natural,
            highlight: String? = nil, theme: ReadingTheme = .light,
            mentionLevel: Int = 3,
            mentionUnderline: MentionUnderlineStyle = MentionUnderlineStyle()
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
                        let color =
                            mentionUnderline.color.map { UIColor($0) }
                            ?? UIColor(theme.link).withAlphaComponent(0.6)
                        let underlineStyle: NSUnderlineStyle =
                            mentionUnderline.thick ? [.single, .thick] : .single
                        attributes[.underlineStyle] = underlineStyle.rawValue
                        attributes[.underlineColor] = color
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
            // 可选中：长按就能选词、复制（见 0053）。链接由 UITextViewDelegate 处理
            view.isSelectable = true
            view.backgroundColor = .clear
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.dataDetectorTypes = []
            // 链接的颜色与下划线由富文本自己决定（自动链接是淡下划线，不是链接蓝）
            view.linkTextAttributes = [:]
            view.delegate = context.coordinator
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

            /// 点链接：交给 App 内部跳转，不让系统拿去开 Safari。
            func textView(
                _ textView: UITextView, primaryActionFor textItem: UITextItem,
                defaultAction: UIAction
            ) -> UIAction? {
                guard case .link(let url) = textItem.content else { return defaultAction }
                let handler = onOpenLink
                return UIAction { _ in
                    MainActor.assumeIsolated { handler?(url) }
                }
            }

            /// 长按链接：默认菜单里的"打开链接"会跳出 App，这里换成自己的两项。
            func textView(
                _ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                defaultMenu: UIMenu
            ) -> UITextItem.MenuConfiguration? {
                guard case .link(let url) = textItem.content else {
                    return .init(menu: defaultMenu)
                }
                let text = (textView.text as NSString).substring(with: textItem.range)
                let open = UIAction(title: "打开") { [weak self] _ in
                    let handler = self?.onOpenLink
                    MainActor.assumeIsolated { handler?(url) }
                }
                let copy = UIAction(title: "复制文字") { _ in
                    MainActor.assumeIsolated { UIPasteboard.general.string = text }
                }
                return .init(menu: UIMenu(children: [open, copy]))
            }
        }
    }
#else

    import AppKit

    /// macOS 正文：用 NSTextView 渲染，和 iOS 一样能精确控制链接、选中与下划线粗细。
    struct BodyText: View {
        let runs: [Run]
        let fontSize: CGFloat
        var alignment: NSTextAlignment = .natural
        var skipFloatedImage = false
        var highlight: String?
        var theme: ReadingTheme = .light
        var onOpenLink: (@MainActor (URL) -> Void)?
        @Environment(\.mentionUnderline) private var mentionUnderline

        @Environment(\.mentionLevel) private var mentionLevel

        var body: some View {
            MacBodyLabel(
                attributed: Self.attributed(
                    runs: runs, fontSize: fontSize, alignment: alignment,
                    highlight: highlight, theme: theme, mentionLevel: mentionLevel,
                    mentionUnderline: mentionUnderline),
                onOpenLink: onOpenLink)
        }

        static func attributed(
            runs: [Run], fontSize: CGFloat, alignment: NSTextAlignment = .natural,
            highlight: String? = nil, theme: ReadingTheme = .light,
            mentionLevel: Int = 3,
            mentionUnderline: MentionUnderlineStyle = MentionUnderlineStyle()
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = fontSize * (Reading.lineHeightMultiple - 1)
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
                        let color =
                            mentionUnderline.color.map { NSColor($0) }
                            ?? NSColor(theme.link).withAlphaComponent(0.6)
                        let underlineStyle: NSUnderlineStyle =
                            mentionUnderline.thick ? [.single, .thick] : .single
                        attributes[.underlineStyle] = underlineStyle.rawValue
                        attributes[.underlineColor] = color
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
                        pieceAttributes[.backgroundColor] =
                            NSColor(theme.link).withAlphaComponent(0.22)
                    }
                    // 关掉自动链接后，这些 run 就当普通文字
                    if let href = run.href, let url = URL(string: href),
                        !(run.m != nil && !mention)
                    {
                        pieceAttributes[.link] = url
                    }
                    result.append(
                        NSAttributedString(string: segment, attributes: pieceAttributes))
                }
            }
            return result
        }

        private static func font(for run: Run, size: CGFloat) -> NSFont {
            var traits: NSFontDescriptor.SymbolicTraits = []
            if run.b == 1 { traits.insert(.bold) }
            if run.i == 1 { traits.insert(.italic) }

            let base = NSFont.systemFont(ofSize: size)
            guard !traits.isEmpty else { return base }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        private static func color(for run: Run, theme: ReadingTheme) -> NSColor {
            NSColor(AttributedText.resolvedColor(for: run, theme: theme))
        }
    }

    private struct MacBodyLabel: NSViewRepresentable {
        let attributed: NSAttributedString
        var onOpenLink: (@MainActor (URL) -> Void)?

        func makeCoordinator() -> Coordinator { Coordinator(onOpenLink: onOpenLink) }

        func makeNSView(context: Context) -> NSTextView {
            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.drawsBackground = false
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.lineBreakMode = .byWordWrapping
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude)
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            // 链接颜色/下划线由富文本自己决定
            textView.linkTextAttributes = [:]
            textView.delegate = context.coordinator
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return textView
        }

        func updateNSView(_ textView: NSTextView, context: Context) {
            context.coordinator.onOpenLink = onOpenLink
            textView.textStorage?.setAttributedString(attributed)
            textView.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize, nsView: NSTextView, context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0,
                let container = nsView.textContainer,
                let layout = nsView.layoutManager
            else { return nil }
            container.containerSize = NSSize(
                width: width, height: CGFloat.greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            var onOpenLink: (@MainActor (URL) -> Void)?

            init(onOpenLink: (@MainActor (URL) -> Void)?) {
                self.onOpenLink = onOpenLink
            }

            func textView(
                _ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int
            ) -> Bool {
                let url: URL? =
                    (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
                guard let url, let handler = onOpenLink else { return false }
                MainActor.assumeIsolated { handler(url) }
                // 返回 true 表示这次点击已经处理；返回 false 的话 AppKit 还会自己
                // open 一次，内链会被 Safari/Finder 再打开一遍。
                return true
            }
        }
    }

#endif
