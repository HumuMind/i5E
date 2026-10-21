import SwiftUI
import ContentKit

#if canImport(UIKit)
import UIKit

/// 两端对齐的段落。
///
/// SwiftUI 的 `Text` 没有 text-align: justify，只能落到 UIKit 的
/// `NSParagraphStyle.alignment = .justified`。这是 0011 里定了的对齐方式的代价：
/// 每个正文段落走一层 `UIViewRepresentable`。
struct JustifiedText: View {
    let runs: [Run]
    let fontSize: CGFloat

    var body: some View {
        JustifiedLabel(attributed: Self.attributed(runs: runs, fontSize: fontSize))
    }

    static func attributed(runs: [Run], fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = fontSize * (Reading.lineHeightMultiple - 1)
        // 中文行禁则：把不能出现在行首的标点挤回上一行
        paragraph.lineBreakStrategy = .pushOut

        let result = NSMutableAttributedString()
        for run in runs {
            guard let text = run.t, !text.isEmpty else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(for: run, size: fontSize),
                .paragraphStyle: paragraph,
                .foregroundColor: color(for: run),
            ]
            if run.u == 1 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.s == 1 { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: text, attributes: attributes))
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

    private static func color(for run: Run) -> UIColor {
        guard let hex = run.c, let color = Color(hex: hex) else { return .label }
        return UIColor(color)
    }
}

#endif

#if canImport(UIKit)

private struct JustifiedLabel: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ view: UILabel, context: Context) {
        view.attributedText = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

#else

/// macOS 上没有 UIKit；先用 SwiftUI 的 Text，两端对齐在 Mac 端待补（可用 NSTextView）。
struct JustifiedText: View {
    let runs: [Run]
    let fontSize: CGFloat

    var body: some View {
        Text(AttributedText.make(runs, size: fontSize))
            .lineSpacing(Reading.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
