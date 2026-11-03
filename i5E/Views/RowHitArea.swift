import SwiftUI

extension View {
    /// 把 List 行的命中区域铺满整行（含文字右侧的空白）。
    ///
    /// `List` 里用 `Button` 做的行，默认只有 label 的内容范围能点：文字
    /// 旁边的空白点不动，按下去的反馈也只跟着文字走。先撑满宽度、再重设
    /// 命中形状，整行才像一个按钮。
    func rowHitArea() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
