import ContentKit
import SwiftUI

/// 设置内容。外层由 `OverlayPanel` 提供卡片与关闭行为。
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    private enum Page {
        case main
        case mentionUnderline
        #if os(macOS)
            case shortcuts
        #endif
    }

    #if os(macOS)
        // 调试/截图用：`-openShortcuts 1` / `-openMentionUnderline 1`
        @State private var page: Page =
            UserDefaults.standard.bool(forKey: "openShortcuts")
            ? .shortcuts
            : (UserDefaults.standard.bool(forKey: "openMentionUnderline")
                ? .mentionUnderline : .main)
    #else
        @State private var page: Page =
            UserDefaults.standard.bool(forKey: "openMentionUnderline")
            ? .mentionUnderline : .main
    #endif

    var body: some View {
        switch page {
        case .main:
            settingsForm
        case .mentionUnderline:
            MentionUnderlineView { page = .main }
        #if os(macOS)
            case .shortcuts:
                ShortcutsView { page = .main }
        #endif
        }
    }

    private var settingsForm: some View {
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

            Section {
                Picker(
                    "自动链接",
                    selection: Binding(
                        get: { model.mentionLevel },
                        set: { model.setMentionLevel($0) })
                ) {
                    Text("关闭").tag(0)
                    Text("精简").tag(1)
                    Text("标准").tag(2)
                    Text("详细").tag(3)
                }
                .pickerStyle(.segmented)

                Text(
                    "正文里提到的条目会带一条淡下划线，点一下跳到它自己的页面。"
                        + "越往下链接越多：精简只连较少见的专名，详细连「生命值」「伤害」这类通用词。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    page = .mentionUnderline
                } label: {
                    HStack {
                        Text("下划线样式")
                        Spacer()
                        Text(model.hasCustomMentionUnderline ? "自定义" : "默认")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("跳转")
            }

            #if os(macOS)
                Section("快捷键") {
                    Button {
                        page = .shortcuts
                    } label: {
                        HStack {
                            Text("配置快捷键")
                            Spacer()
                            Text("\(model.shortcut(for: .search).display) 等")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            #endif

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
