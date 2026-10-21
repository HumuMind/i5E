import ContentKit
import SwiftUI

/// 排版常量，来自 Docs/decisions/0011-typography.md。
enum Reading {
    static let measure: CGFloat = 720  // 版心
    static let bodySize: CGFloat = 19  // 正文字号
    static let lineHeightMultiple: CGFloat = 1.8
    static var lineSpacing: CGFloat { bodySize * (lineHeightMultiple - 1) }
}

struct ReaderView: View {
    let page: Page

    @Environment(AppModel.self) private var model

    private var focus: AppModel.Focus? { model.focus }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { index, block in
                        BlockView(block: block, highlight: focus?.query)
                            .id(index)
                    }
                }
                .frame(maxWidth: Reading.measure, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .task(id: focus) {
                guard let focus else { return }
                // 等一帧，等布局出来再滚，否则 scrollTo 会落空
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(focus.blockIndex, anchor: .top)
                }
            }
        }
        .navigationTitle(page.title.isEmpty ? page.path : page.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
