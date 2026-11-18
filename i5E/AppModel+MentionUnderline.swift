import ContentKit
import SwiftUI

extension AppModel {
    var mentionUnderlineStyle: MentionUnderlineStyle {
        MentionUnderlineStyle(
            color: state.mentionUnderlineColor.flatMap { Color(hex: $0) },
            thick: state.mentionUnderlineThick ?? false)
    }

    var mentionUnderlineColorHex: String? { state.mentionUnderlineColor }
    var isMentionUnderlineThick: Bool { state.mentionUnderlineThick ?? false }
    var hasCustomMentionUnderline: Bool {
        state.mentionUnderlineColor != nil || state.mentionUnderlineThick != nil
    }

    func setMentionUnderlineColor(_ hex: String) {
        state.mentionUnderlineColor = hex
        store.saveState(state)
    }

    func setMentionUnderlineThick(_ thick: Bool) {
        state.mentionUnderlineThick = thick ? true : nil
        store.saveState(state)
    }

    func resetMentionUnderline() {
        state.mentionUnderlineColor = nil
        state.mentionUnderlineThick = nil
        store.saveState(state)
    }
}
