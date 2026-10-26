import ContentKit
import SwiftUI

/// 设置内容。外层由 `OverlayPanel` 提供卡片与关闭行为。
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(
                    "字号",
                    selection: Binding(
                        get: { ReadingMetrics.step(for: model.metrics.bodySize) },
                        set: { model.setFontStep($0) }
                    )
                ) {
                    ForEach(ReadingMetrics.Step.allCases) { step in
                        Text(step.title).tag(step)
                    }
                }
                .pickerStyle(.segmented)

                Text("版心与表格字号会跟着等比调整，每行字数保持在 33–42 字。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("阅读字号")
            }

            Section("内容") {
                LabeledContent("页面", value: "\(model.pageCount)")
                if let build = model.contentBuild {
                    LabeledContent(
                        "上游版本", value: "\(build.upstream.short) · \(build.upstreamDate)")
                    if let subject = build.upstream.subject, !subject.isEmpty {
                        LabeledContent("提交", value: subject)
                    }
                }
                LabeledContent("应用版本", value: Self.appVersion)
            }

            Section("说明") {
                Text("内容来自 DND5e_chm，免费、离线、无账号。内容纠错请提交到上游项目。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("代码许可", value: "MIT")
                LabeledContent("内容授权", value: "GPL-3.0（沿用上游）")
                Text("文本与美术素材的著作权归 Wizards of the Coast 及相应译者所有。本项目非官方、非商业。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
