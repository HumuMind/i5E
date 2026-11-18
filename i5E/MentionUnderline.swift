import SwiftUI

/// 自动链接下划线的外观。
struct MentionUnderlineStyle: Equatable {
    /// nil 表示跟随主题的默认淡色。
    var color: Color?
    /// 是否用系统的粗下划线（NSUnderlineStyle.thick）。
    var thick = false
}

private struct MentionUnderlineKey: EnvironmentKey {
    static let defaultValue = MentionUnderlineStyle()
}

extension EnvironmentValues {
    var mentionUnderline: MentionUnderlineStyle {
        get { self[MentionUnderlineKey.self] }
        set { self[MentionUnderlineKey.self] = newValue }
    }
}
