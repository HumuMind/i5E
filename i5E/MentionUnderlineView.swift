import SwiftUI

/// 设置二级页：自动链接的下划线颜色和粗细。
struct MentionUnderlineView: View {
    var onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSubpageHeader(title: "自动链接下划线") { onBack() }
            Divider().overlay(theme.border)

            Form {
                Section {
                    ColorPicker(
                        "下划线颜色",
                        selection: underlineColorBinding,
                        supportsOpacity: true)

                    Picker("粗细", selection: underlineThickBinding) {
                        Text("标准").tag(false)
                        Text("粗").tag(true)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动链接示例")
                            .font(.callout)
                        Rectangle()
                            .fill(underlineColor)
                            .frame(
                                width: 96,
                                height: model.isMentionUnderlineThick ? 2 : 1)
                    }
                    .padding(.vertical, 2)

                    Button("恢复默认下划线") {
                        model.resetMentionUnderline()
                    }
                    .disabled(!model.hasCustomMentionUnderline)
                } footer: {
                    Text(
                        "默认是跟随主题的淡色细线。自定义颜色同时用于浅色和深色模式；"
                            + "粗细提供标准/粗两档，作用于正文段落，标题、列表和表格等系统文本只应用颜色。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .background(theme.surface)
    }

    private var underlineColor: Color {
        if let hex = model.mentionUnderlineColorHex, let color = Color(hex: hex) {
            return color
        }
        return theme.link.opacity(0.6)
    }

    private var underlineColorBinding: Binding<Color> {
        Binding(
            get: { underlineColor },
            set: { model.setMentionUnderlineColor($0.rgbaHex) })
    }

    private var underlineThickBinding: Binding<Bool> {
        Binding(
            get: { model.isMentionUnderlineThick },
            set: { model.setMentionUnderlineThick($0) })
    }
}
