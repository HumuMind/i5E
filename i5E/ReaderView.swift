import SwiftUI
import ContentKit

/// 排版常量，来自 Docs/decisions/0011-typography.md。
enum Reading {
    static let measure: CGFloat = 720  // 版心
    static let bodySize: CGFloat = 19  // 正文字号
    static let lineHeightMultiple: CGFloat = 1.8
    static var lineSpacing: CGFloat { bodySize * (lineHeightMultiple - 1) }
    static let fontSizeScale: CGFloat = 1.0
}

struct ReaderView: View {
    let page: Page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
            }
            .frame(maxWidth: Reading.measure, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(page.title.isEmpty ? page.path : page.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
