import ContentKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension Color {
    /// 接受 `#rrggbb` / `rrggbb` / `#rrggbbaa` / `rrggbbaa`。
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else {
            return nil
        }
        if s.count == 6 {
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: 1)
        } else {
            self.init(
                .sRGB,
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255)
        }
    }

    /// 转成 `#rrggbbaa`（sRGB），用于把自定义下划线颜色存进 ReaderState。
    var rgbaHex: String {
        #if canImport(UIKit)
            let resolved = UIColor(self)
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
                return "#000000FF"
            }
        #elseif canImport(AppKit)
            let resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
            let r = resolved.redComponent
            let g = resolved.greenComponent
            let b = resolved.blueComponent
            let a = resolved.alphaComponent
        #else
            return "#000000FF"
        #endif

        func byte(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
    }
}
