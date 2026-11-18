import SwiftUI

/// 设置二级页的返回头。
struct SettingsSubpageHeader: View {
    let title: String
    var onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Label("设置", systemImage: "chevron.backward")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)

            Spacer()
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.text)
            Spacer()
            // 和返回按钮宽度对称，让标题保持在中间
            Color.clear.frame(width: 46, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
