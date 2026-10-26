import CoreGraphics

/// 排版尺寸：字号可调，版心与行距按比例跟随。
public struct ReadingMetrics: Sendable, Equatable {
    public var bodySize: CGFloat
    public var measure: CGFloat
    public var lineSpacing: CGFloat { bodySize * 0.8 }

    public static let standard = ReadingMetrics(bodySize: 19, measure: 720)

    /// 左右留白：按宽度的 8% 计算，最多 160pt。
    ///
    /// 用比例而不是固定值——固定 160pt 在 834pt 的 iPad 上会吃掉太多，
    /// 版心只剩 514pt（每行 27 字）；按比例则 iPad 接近原来的 720，
    /// Mac 宽窗口才明显变宽。
    public static let sideMarginRatio: CGFloat = 0.08
    public static let maxSideMargin: CGFloat = 160
    /// 每行字数的上限。超过这个宽度眼睛回行容易错位，所以版心还要封顶。
    public static let maxCharactersPerLine: CGFloat = 45

    /// 按可用宽度算版心：左右按比例留白，宽度不超过 45 个字。
    public func measure(forAvailable width: CGFloat) -> CGFloat {
        let margin = min(Self.maxSideMargin, max(24, width * Self.sideMarginRatio))
        let available = max(280, width - margin * 2)
        return min(available, bodySize * Self.maxCharactersPerLine)
    }

    public init(bodySize: CGFloat, measure: CGFloat) {
        self.bodySize = bodySize
        self.measure = measure
    }

    public static func forSize(_ size: CGFloat) -> ReadingMetrics {
        ReadingMetrics(bodySize: size, measure: (720 * size / 19).rounded())
    }

    /// 字号档位，供设置页使用。
    public enum Step: Double, CaseIterable, Identifiable {
        case small = 17
        case standard = 19
        case large = 22

        public var id: Double { rawValue }
        public var title: String {
            switch self {
            case .small: "小"
            case .standard: "标准"
            case .large: "大"
            }
        }
        public var metrics: ReadingMetrics { .forSize(rawValue) }
    }

    public static func step(for size: Double) -> Step {
        Step.allCases.min { abs($0.rawValue - size) < abs($1.rawValue - size) } ?? .standard
    }

    /// 表格字号阶梯：19 → 16 → 13，按字号档位等比缩放，下限 12。
    public func tableSize(columnCount: Int) -> CGFloat {
        let base: CGFloat
        switch columnCount {
        case ...2: base = bodySize
        case 3...4: base = 16
        default: base = 13
        }
        return max(12, (base * bodySize / 19).rounded())
    }
}
