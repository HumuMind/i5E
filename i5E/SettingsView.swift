import ContentKit
import SwiftUI

/// 设置。目前只有阅读字号，其余留给以后（主题、同步等）。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                    LabeledContent("版本", value: Self.appVersion)
                }

                Section("说明") {
                    Text("内容来自 DND5e_chm，免费、离线、无账号。内容纠错请提交到上游项目。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
