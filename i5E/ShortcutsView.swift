#if os(macOS)
    import AppKit
    import ContentKit
    import SwiftUI

    /// 设置里的二级页：列出快捷键，点一下开始录制。
    struct ShortcutsView: View {
        var onBack: () -> Void

        @Environment(AppModel.self) private var model
        @Environment(\.colorScheme) private var colorScheme
        @State private var recording: ShortcutAction?
        @State private var showClickModifiers = false

        private var theme: ReadingTheme { .resolve(colorScheme) }

        var body: some View {
            VStack(spacing: 0) {
                SettingsSubpageHeader(title: "快捷键") { onBack() }
                Divider().overlay(theme.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ShortcutAction.Group.allCases) { group in
                            let actions = ShortcutAction.allCases.filter { $0.group == group }
                            Text(group.rawValue)
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                            ForEach(actions) { action in
                                row(action)
                                if action != actions.last {
                                    Divider().overlay(theme.border.opacity(0.5))
                                }
                            }
                        }

                        Button("恢复全部默认") {
                            model.resetAllShortcuts()
                            MenuShortcuts.apply(model)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 18)

                        Text(
                            "点击右侧快捷键后按下新的组合键，Esc 取消。"
                                + "至少需要 ⌘、⌃ 或 ⌥，且不能和其他动作重复。"
                                + "「在新标签页打开链接」是点击修饰键，在弹层里勾选。"
                        )
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(theme.surface)
            .overlay {
                if let action = recording {
                    ShortcutRecorder(action: action) {
                        recording = nil
                    }
                }
            }
        }

        private func row(_ action: ShortcutAction) -> some View {
            HStack(spacing: 10) {
                Text(action.title)
                    .font(.callout)
                    .foregroundStyle(theme.text)
                Spacer()

                if action.isClickModifier {
                    // 点击修饰键不是一个键盘组合，弹一个勾选面板
                    Button {
                        showClickModifiers = true
                    } label: {
                        shortcutChip(action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shortcut.record.\(action.rawValue)")
                    .popover(isPresented: $showClickModifiers, arrowEdge: .bottom) {
                        clickModifierPicker(action)
                    }
                } else {
                    Button {
                        recording = action
                    } label: {
                        shortcutChip(action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shortcut.record.\(action.rawValue)")
                }

                if model.hasCustomShortcut(for: action) {
                    Button {
                        model.resetShortcut(for: action)
                        MenuShortcuts.apply(model)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("恢复默认")
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }

        private func shortcutChip(_ action: ShortcutAction) -> some View {
            Text(model.shortcut(for: action).display)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.background, in: .rect(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(theme.border, lineWidth: 0.5)
                )
        }

        private func clickModifierPicker(_ action: ShortcutAction) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("在新标签页打开链接")
                    .font(.headline)
                Text("按住选中的修饰键点击链接。")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                ForEach(ClickModifier.allCases) { modifier in
                    Toggle(
                        modifier.title,
                        isOn: Binding(
                            get: { model.isLinkClickModifierEnabled(modifier) },
                            set: { model.setLinkClickModifier(modifier, enabled: $0) }
                        ))
                }
                Text("至少保留一个。⌘ 最稳；⌃ 可能被系统当成右键，⇧/⌥ 可能和选择手势冲突。")
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
                    .frame(width: 230, alignment: .leading)
            }
            .padding(14)
            .frame(width: 250)
        }
    }

    // MARK: - 录制

    private struct ShortcutRecorder: View {
        let action: ShortcutAction
        var onFinish: () -> Void

        @Environment(AppModel.self) private var model
        @Environment(\.colorScheme) private var colorScheme
        @State private var monitor: Any?
        @State private var message: String?

        private var theme: ReadingTheme { .resolve(colorScheme) }

        var body: some View {
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()

                VStack(spacing: 10) {
                    Text("按下新的快捷键")
                        .font(.headline)
                        .foregroundStyle(theme.text)
                    Text(action.title)
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("Esc 取消")
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                    Button("取消") { finish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 2)
                }
                .padding(24)
                .frame(width: 300)
                .background(theme.surface, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            }
            .onAppear { start() }
            .onDisappear { stop() }
        }

        private func start() {
            model.isRecordingShortcut = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handle(event)
                return nil
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            model.isRecordingShortcut = false
        }

        private func finish() {
            stop()
            onFinish()
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == 53 {
                finish()
                return
            }
            guard let shortcut = KeyShortcut(event: event) else {
                message = "至少需要 ⌘、⌃ 或 ⌥"
                return
            }
            if model.isReservedShortcut(shortcut, for: action) {
                message = "这个组合被系统占用了"
                return
            }
            if let conflict = model.conflictingAction(for: shortcut, excluding: action) {
                message = "已被「\(conflict.title)」使用"
                return
            }
            model.setShortcut(shortcut, for: action)
            MenuShortcuts.apply(model)
            finish()
        }
    }
#endif
