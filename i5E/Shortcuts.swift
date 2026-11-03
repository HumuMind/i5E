import ContentKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// 可配置的快捷键动作。`rawValue` 是 `ReaderState.shortcuts` 的键。
enum ShortcutAction: String, CaseIterable, Identifiable {
    case back
    case forward
    case search
    case previousPage
    case nextPage
    case toggleBookmark
    case increaseFont
    case decreaseFont
    case newTab
    case closeTab
    case openLinkInNewTab

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case navigation = "导航"
        case reading = "阅读"
        case tabs = "标签页"

        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .back, .forward:
            .navigation
        case .search, .previousPage, .nextPage, .toggleBookmark, .increaseFont, .decreaseFont:
            .reading
        case .newTab, .closeTab, .openLinkInNewTab:
            .tabs
        }
    }

    var title: String {
        switch self {
        case .back: "后退"
        case .forward: "前进"
        case .search: "搜索正文"
        case .previousPage: "上一页"
        case .nextPage: "下一页"
        case .toggleBookmark: "添加或移除书签"
        case .increaseFont: "放大字号"
        case .decreaseFont: "缩小字号"
        case .newTab: "新建标签页"
        case .closeTab: "关闭标签页"
        case .openLinkInNewTab: "在新标签页打开链接"
        }
    }

    var defaultShortcut: KeyShortcut {
        switch self {
        case .back: KeyShortcut(key: "[", command: true)
        case .forward: KeyShortcut(key: "]", command: true)
        case .search: KeyShortcut(key: "f", command: true)
        case .previousPage: KeyShortcut(key: "upArrow", command: true)
        case .nextPage: KeyShortcut(key: "downArrow", command: true)
        case .toggleBookmark: KeyShortcut(key: "b", command: true)
        case .increaseFont: KeyShortcut(key: "=", command: true)
        case .decreaseFont: KeyShortcut(key: "-", command: true)
        case .newTab: KeyShortcut(key: "t", command: true)
        case .closeTab: KeyShortcut(key: "w", command: true)
        case .openLinkInNewTab: KeyShortcut(key: "click", command: true)
        }
    }

    /// 这个"快捷键"不是键盘组合，而是点击链接时要按住的修饰键。
    var isClickModifier: Bool { self == .openLinkInNewTab }

    /// 菜单项的标题 → 动作。`MenuShortcuts` 靠它同步菜单上的按键。
    static func menuAction(for title: String) -> ShortcutAction? {
        allCases.first { $0.title == title }
    }
}

/// 点击链接时用来开新标签页的修饰键。默认是 ⌘，可以改。
enum ClickModifier: String, CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        }
    }
}

// MARK: - 展示与 SwiftUI 映射

extension KeyShortcut {
    /// 供菜单和快捷键录制器展示，如 `⌘⇧F`。
    var display: String {
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += keyDisplay
        return result
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "upArrow": .upArrow
        case "downArrow": .downArrow
        case "leftArrow": .leftArrow
        case "rightArrow": .rightArrow
        case "return": .return
        case "space": .space
        case "delete": .delete
        case "escape": .escape
        case "tab": .tab
        case "click":
            // 链接的点击修饰键不会挂到菜单上，这里只作占位
            KeyEquivalent("?")
        default:
            KeyEquivalent((shift ? Self.shifted(key) : key).first ?? "?")
        }
    }

    var keyDisplay: String {
        switch key {
        case "upArrow": "↑"
        case "downArrow": "↓"
        case "leftArrow": "←"
        case "rightArrow": "→"
        case "return": "↩"
        case "space": "空格"
        case "delete": "⌫"
        case "escape": "⎋"
        case "tab": "⇥"
        case "click": "点击"
        default: key.uppercased()
        }
    }

    /// 带 Shift 的字符（按美式键盘）。菜单的 keyEquivalent 要的是"按下 Shift 后"的字符。
    static func shifted(_ key: String) -> String {
        guard key.count == 1, let char = key.first else { return key }
        let map: [Character: Character] = [
            "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&",
            "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{", "]": "}",
            "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~",
        ]
        if let shifted = map[char] { return String(shifted) }
        return String(char).uppercased()
    }
}

#if os(macOS)
    extension KeyShortcut {
        var nsModifiers: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if command { flags.insert(.command) }
            if shift { flags.insert(.shift) }
            if option { flags.insert(.option) }
            if control { flags.insert(.control) }
            return flags
        }

        /// NSMenuItem 的 keyEquivalent。
        var menuKeyEquivalent: String {
            switch key {
            case "upArrow": String(UnicodeScalar(NSUpArrowFunctionKey)!)
            case "downArrow": String(UnicodeScalar(NSDownArrowFunctionKey)!)
            case "leftArrow": String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            case "rightArrow": String(UnicodeScalar(NSRightArrowFunctionKey)!)
            case "return": "\r"
            case "space": " "
            case "delete": String(UnicodeScalar(NSDeleteCharacter)!)
            case "escape": "\u{1B}"
            case "tab": "\t"
            case "click": ""
            default: shift ? Self.shifted(key) : key
            }
        }

        /// 用一次按键事件构造快捷键。没有 ⌘/⌃/⌥ 时返回 nil（避免占用普通打字键）。
        init?(event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command)
            let shift = flags.contains(.shift)
            let option = flags.contains(.option)
            let control = flags.contains(.control)
            guard command || control || option else { return nil }
            guard let key = Self.key(for: event), key != "escape" else { return nil }
            self.init(
                key: key, command: command, shift: shift, option: option, control: control)
        }

        static func key(for event: NSEvent) -> String? {
            switch event.keyCode {
            case 123: return "leftArrow"
            case 124: return "rightArrow"
            case 125: return "downArrow"
            case 126: return "upArrow"
            case 36: return "return"
            case 49: return "space"
            case 51: return "delete"
            case 53: return "escape"
            case 48: return "tab"
            default:
                guard let characters = event.charactersIgnoringModifiers,
                    characters.count == 1, let char = characters.first
                else { return nil }
                return String(char).lowercased()
            }
        }

        func matches(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) == command,
                flags.contains(.shift) == shift,
                flags.contains(.option) == option,
                flags.contains(.control) == control
            else { return false }
            return Self.key(for: event) == key
        }
    }

    /// 把配置同步到 SwiftUI 生成的菜单项上。
    ///
    /// `commands` 只在场景重建时重算，改完快捷键后直接改 `NSMenuItem` 最稳。
    @MainActor
    enum MenuShortcuts {
        static func apply(_ model: AppModel) {
            guard let main = NSApp.mainMenu else { return }
            for top in main.items {
                guard let submenu = top.submenu else { continue }
                for item in submenu.items {
                    guard let action = ShortcutAction.menuAction(for: item.title) else {
                        continue
                    }
                    let shortcut = model.shortcut(for: action)
                    item.keyEquivalent = shortcut.menuKeyEquivalent
                    item.keyEquivalentModifierMask = shortcut.nsModifiers
                }
            }
        }
    }
#endif
