import ContentKit
import Foundation

extension AppModel {

    /// 某个动作当前生效的快捷键：用户改过的优先，否则用默认值。
    func shortcut(for action: ShortcutAction) -> KeyShortcut {
        state.shortcuts[action.rawValue] ?? action.defaultShortcut
    }

    func hasCustomShortcut(for action: ShortcutAction) -> Bool {
        state.shortcuts[action.rawValue] != nil
    }

    func setShortcut(_ shortcut: KeyShortcut, for action: ShortcutAction) {
        state.shortcuts[action.rawValue] = shortcut
        store.saveState(state)
        shortcutRevision += 1
    }

    func resetShortcut(for action: ShortcutAction) {
        state.shortcuts.removeValue(forKey: action.rawValue)
        store.saveState(state)
        shortcutRevision += 1
    }

    func resetAllShortcuts() {
        state.shortcuts = [:]
        store.saveState(state)
        shortcutRevision += 1
    }

    // MARK: - 链接的点击修饰键

    func isLinkClickModifierEnabled(_ modifier: ClickModifier) -> Bool {
        let shortcut = shortcut(for: .openLinkInNewTab)
        switch modifier {
        case .command: return shortcut.command
        case .option: return shortcut.option
        case .control: return shortcut.control
        case .shift: return shortcut.shift
        }
    }

    func setLinkClickModifier(_ modifier: ClickModifier, enabled: Bool) {
        var shortcut = shortcut(for: .openLinkInNewTab)
        switch modifier {
        case .command: shortcut.command = enabled
        case .option: shortcut.option = enabled
        case .control: shortcut.control = enabled
        case .shift: shortcut.shift = enabled
        }
        // 至少保留一个修饰键，否则普通点击也会开新 tab
        if !(shortcut.command || shortcut.option || shortcut.control || shortcut.shift) {
            shortcut.command = true
        }
        setShortcut(shortcut, for: .openLinkInNewTab)
    }

    /// 和别的动作撞车时返回那个动作。
    func conflictingAction(
        for shortcut: KeyShortcut, excluding action: ShortcutAction
    ) -> ShortcutAction? {
        ShortcutAction.allCases.first { other in
            other != action && self.shortcut(for: other) == shortcut
        }
    }

    /// 系统或窗口本身占用的组合，不允许改给别的动作。
    func isReservedShortcut(_ shortcut: KeyShortcut, for action: ShortcutAction) -> Bool {
        guard shortcut.command else { return false }
        switch shortcut.key {
        case "q", ",":
            return true
        // ⌘W 留给关闭窗口；closeTab 自己可以用
        case "w":
            return action != .closeTab
        default:
            return false
        }
    }
}
