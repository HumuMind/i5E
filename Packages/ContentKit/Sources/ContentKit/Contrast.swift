import Foundation

/// 一个不依赖 UI 框架的 RGB 颜色（分量 0…1）。
public struct RGB: Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// 接受 `#rrggbb`、`rrggbb`，或 `rgb(r,g,b)`。
    public init?(hexOrRGB text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("rgb") {
            let digits = trimmed.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = digits.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count >= 3 else { return nil }
            self.init(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255)
            return
        }
        var value = trimmed
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            r: Double((number >> 16) & 0xFF) / 255,
            g: Double((number >> 8) & 0xFF) / 255,
            b: Double(number & 0xFF) / 255)
    }

    public var hex: String {
        let clamp = { (x: Double) in Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }

    /// WCAG 相对亮度。
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

/// 对比度修复，移植自上游 WebHelp 的 `webhelp-contrast.js`。
///
/// 思路不是"把颜色映射成语义 token"，而是：算前景对背景的对比度，
/// 不达标就朝黑或朝白混合，二分找到**刚好达标且离原色最近**的那个。
/// 这样既保证可读，又尽量保留色相——深色下的暗红会变成浅红，而不是灰色。
public enum Contrast {

    /// WCAG AA 正文阈值。上游用的也是这个。
    public static let minimumRatio: Double = 4.5

    public static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let a = first.luminance
        let b = second.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static func mix(_ first: RGB, _ second: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(
            r: first.r + (second.r - first.r) * t,
            g: first.g + (second.g - first.g) * t,
            b: first.b + (second.b - first.b) * t)
    }

    /// 返回一个对比度达标、且尽量接近原色的颜色。已经达标则原样返回。
    public static func repair(
        _ foreground: RGB, on background: RGB,
        minimum: Double = minimumRatio
    ) -> RGB {
        guard ratio(foreground, background) < minimum else { return foreground }

        let targets = [RGB(r: 0, g: 0, b: 0), RGB(r: 1, g: 1, b: 1)]
            .filter { ratio($0, background) >= minimum }

        var best: RGB?
        var bestDistance = Double.greatestFiniteMagnitude

        for target in targets {
            var low = 0.0
            var high = 1.0
            for _ in 0..<18 {
                let middle = (low + high) / 2
                if ratio(mix(foreground, target, middle), background) >= minimum {
                    high = middle
                } else {
                    low = middle
                }
            }
            let candidate = mix(foreground, target, high)
            let dr = candidate.r - foreground.r
            let dg = candidate.g - foreground.g
            let db = candidate.b - foreground.b
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }

        if let best { return best }
        // 黑白都不达标（背景极端时）——取对比度更高的那个
        return targets.max { ratio($0, background) < ratio($1, background) }
            ?? RGB(r: 1, g: 1, b: 1)
    }

    /// 深色模式下把浅色底压暗：与原背景混合，保留色相、压到深色区间。
    public static func darken(_ background: RGB, toward surface: RGB, amount: Double = 0.88) -> RGB {
        mix(background, surface, min(0.97, max(0, amount)))
    }
}
